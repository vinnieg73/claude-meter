import Foundation

/// `ClaudeMeter --replay`: steps the real meter code through this Mac's history log and
/// transcripts with a moving clock, from a blank state (calibration is learned along the way),
/// and checks what has to hold. Reads, never writes. Exits non-zero on any failure.
///
/// 1. Window openings: after each reset, the meter's estimate of the next window's reset
///    matches the real one (from the history log) within a minute, or is one 10-minute slot late
///    when the first message was logged within a minute of a mark (the logs can't tell which).
/// 2. Probe gate: between a reset and the next message, a probe would not run (it would open
///    a window); right after that message it would.
/// 3. Alerts: none goes out twice for the same window.
/// 4. Accuracy: estimates made just before each exact reading are within the bar.
/// 5. Consistency: every threshold, cap warning and runaway the dropdown called for was alerted;
///    the early resets the meter recorded are the ones the readings show; the "This week" shares
///    never add up to more than the weekly card; History's windows don't overlap or peak above
///    their own readings.
/// 6. Synthetic: made-up early resets, lapsed windows and probe-gate edges the log may never hold.
/// Each reading is replayed with only the windows it measured, not ones carried over.
@MainActor
enum Replay {
    /// Typical (mean absolute) error allowed, in points.
    static let accuracyBar = (fiveHour: 1.5, weekly: 1.0)
    /// What a run has to cover to mean anything: a check that never ran (calibration broken, data
    /// gone) must fail, not pass with "no checks".
    static let minimum = (openings: 8, gate: 15, accuracy: 30)
    /// How far the estimated growth may be from the measured growth (1.00), as a fraction.
    static let growthBar = 0.12

    static func run() -> Int32 {
        let report = Meter().replay()
        report.lines.forEach { print($0) }
        guard report.failures.isEmpty else {
            report.failures.forEach { print("FAIL: \($0)") }
            return 1
        }
        print("PASS")
        return 0
    }
}

extension Meter {
    struct ReplayReport {
        var lines: [String] = []
        var failures: [String] = []
    }

    /// A reset the replay can check: when it happened, the first message after it, and when the
    /// window that message opened really reset.
    private struct Opening {
        let reset: Date
        let firstMessage: Date
        let realReset: Date
    }

    func replay() -> ReplayReport {
        var report = ReplayReport()
        quiet = true
        store.readOnly = true
        store.state = PersistedState()
        checkLimit = .max // the whole run's checks, not the last 200

        // Every logged turn, read once; at each step the meter is handed those up to its clock. The logs'
        // 8 days are counted back from the newest reading, not from today, so the same history gives the
        // same verdict whenever it's replayed.
        let index = LogIndex()
        let newest = HistoryLog.load().readings.map(\.at).max() ?? Date()
        index.clock = { newest }
        // Read from scratch, not from the app's cache: that holds only what the app's own 8 days
        // kept, and with the horizon counted back from an older reading it would leave a stretch
        // claimed as covered but never read.
        index.refresh()
        let all = index.turns
        coveredFrom = index.coveredFrom
        guard let firstTurn = all.first?.at else {
            report.failures.append("no Claude Code transcripts to replay")
            return report
        }
        // Only readings whose windows the logs cover, and of each only what it measured itself.
        let readings = HistoryLog.load().readings
            .filter { $0.at > firstTurn.addingTimeInterval(5 * 3600) }
            .sorted { $0.at < $1.at }
            .map(Self.measuredOnly)
        guard let start = readings.first?.at, let end = readings.last?.at, readings.count >= 2 else {
            report.failures.append("not enough history to replay (need 2+ exact readings within the logs)")
            return report
        }
        func upTo(_ t: Date) -> Int { // turns at or before t
            var low = 0, high = all.count
            while low < high {
                let mid = (low + high) / 2
                if all[mid].at <= t { low = mid + 1 } else { high = mid }
            }
            return low
        }

        // Each run of 5-hour windows in the history log, and the message that opened each.
        var resets: [Date] = []
        for r in readings {
            guard let w = r.fiveHour else { continue }
            if let last = resets.last, Window.same(last, w.resetsAt) { continue }
            resets.append(w.resetsAt)
        }
        var openings: [Opening] = []
        var openingsMoved = 0, openingsForeign = 0
        for (reset, next) in zip(resets, resets.dropFirst()) {
            let i = upTo(reset)
            guard i < all.count else { continue }
            let first = all[i].at
            let opened = next.addingTimeInterval(-5 * 3600)
            // Only when the next recorded window is the one this message opened.
            guard opened <= first, first < next else { continue }
            // Not one that began before the last one's reset: Anthropic moved that reset itself.
            if opened < reset.addingTimeInterval(-60) { openingsMoved += 1; continue }
            // Not one opened well before this Mac's message (claude.ai, the phone): it can't know.
            if first.timeIntervalSince(opened) > 660 { openingsForeign += 1; continue }
            openings.append(Opening(reset: reset, firstMessage: first, realReset: next))
        }
        /// What the meter knew at a reset: the last reading of the window that ended there.
        func lastBefore(_ reset: Date) -> ExactReading? {
            readings.last { $0.at <= reset && $0.fiveHour != nil }
        }

        // Early resets, read from the readings themselves (the same window measured lower than
        // before), for the meter's own record of them to be held against.
        // The statusline counts as `Meter.pick` takes it: for the same window only a climb (and none once
        // the window was reset early), but a later window from any source.
        var shown: [(at: Date, window: String)] = []
        var heldWindow: [String: Window] = [:]
        var heldRestarted: [String: Bool] = [:]
        for r in readings {
            let tap = r.source == "tap"
            for (name, w, span) in [("5h", r.fiveHour, 5 * 3600.0), ("week", r.weekly, 7 * 86400.0)] {
                guard let w else { continue }
                if let held = heldWindow[name] {
                    if w.resetsAt < held.resetsAt.addingTimeInterval(-900) { continue }
                    if Window.same(held.resetsAt, w.resetsAt) {
                        if tap {
                            if w.pct <= held.pct + 0.5 || heldRestarted[name] == true { continue }
                        } else {
                            // As `Meter.pick` reads it: a fall of more than a few points, or to nothing from a
                            // point or more, is a reset; a smaller one is an old number, and the higher stays held.
                            let toNothing = w.pct < 0.5 && held.pct >= 1
                            if w.pct < held.pct - Meter.restartDrop || toNothing {
                                shown.append((r.at, name))
                                heldRestarted[name] = true
                            } else if w.pct < held.pct - 0.5 {
                                continue
                            }
                        }
                    } else if w.resetsAt.addingTimeInterval(-span) < held.resetsAt.addingTimeInterval(-60) {
                        shown.append((r.at, name)) // a later window that began before the held one was due
                        heldRestarted[name] = true
                    } else {
                        heldRestarted[name] = false
                    }
                }
                heldWindow[name] = w
            }
        }
        // The clock: every 10 minutes, every reading, and the points each check looks at.
        var times = Set<Date>()
        var t = start
        while t <= end {
            times.insert(t)
            t.addTimeInterval(600)
        }
        readings.forEach { times.insert($0.at) }
        for o in openings {
            times.insert(o.reset.addingTimeInterval(30))
            times.insert(o.firstMessage.addingTimeInterval(30))
            times.insert(o.firstMessage.addingTimeInterval(60))
        }

        var alerts: [(at: Date, key: String)] = []
        // When Anthropic reset a window early, which re-arms its alerts.
        var restarts: [(at: Date, window: String)] = []
        let notifier = Notifier(store: store) { [unowned self] key in alerts.append((self.clock(), key)) }
        var gateChecks = 0, openingChecks = 0, openingSkipped = 0, openingSlotBefore = 0
        // Alerts the dropdown called for, and times its week shares added up to too much.
        var owed: [(kind: String, detail: String, resets: Date)] = []
        func owe(_ kind: String, _ detail: String, _ resets: Date) {
            guard !owed.contains(where: { $0.kind == kind && $0.detail == detail && Window.same($0.resets, resets) })
            else { return }
            owed.append((kind, detail, resets))
        }
        var shareBreaches: [(at: Date, shares: Double, week: Double, cap: Double)] = []
        var next = 0
        loaded = true
        for t in times.sorted() {
            clock = { t }
            turns = Array(all[..<upTo(t)])
            while next < readings.count, readings[next].at <= t {
                let before = store.state.lastExact
                absorb(readings[next])
                let after = store.state.lastExact
                if let r = after?.fiveHour?.restartedAt, r != before?.fiveHour?.restartedAt { restarts.append((t, "5h")) }
                if let r = after?.weekly?.restartedAt, r != before?.weekly?.restartedAt { restarts.append((t, "week")) }
                next += 1
            }
            recompute()
            notifier.check(snapshot, now: t, post: true)

            // (A window nothing has measured for a while raises none: see WindowView.stale.)
            for w in [snapshot.fiveHour, snapshot.weekly].compactMap({ $0 }) where !w.idle && !w.stale {
                guard let r = w.resetsAt else { continue }
                for threshold in [80.0, 95.0] where w.pct.rounded() >= threshold { owe(w.title, "\(Int(threshold))", r) }
            }
            if let f = snapshot.fiveHour, let r = f.resetsAt {
                if !f.stale, let capAt = f.capAt, snapshot.capWarning != nil {
                    let lead = capAt.timeIntervalSince(t)
                    if lead > 0, lead <= 1800 { owe("pace", "0", r) }
                }
                for runaway in snapshot.runaways { owe("runaway:\(runaway.id)", "0", r) }
            }
            if let w = snapshot.weekly, !snapshot.weekShares.isEmpty {
                let shares = snapshot.weekShares.reduce(0) { $0 + $1.pct }
                if shares > w.pct + 3 { shareBreaches.append((t, shares, w.pct, store.state.calibration.capWeek ?? 0)) }
            }

            for o in openings {
                if t == o.reset.addingTimeInterval(30), o.firstMessage > o.reset.addingTimeInterval(60) {
                    // Judged from what the meter knew at the reset: a reading taken since then may be
                    // the old probe's (pre-0.8 it ran seconds after a reset and opened the window
                    // itself), and this code wouldn't have taken it.
                    let held = store.state.lastExact
                    store.state.lastExact = lastBefore(o.reset) ?? held
                    let open = windowOpen(t)
                    store.state.lastExact = held
                    gateChecks += 1
                    if open {
                        report.failures.append("probe would run at \(t) with no window open "
                                               + "(reset \(o.reset), next message \(o.firstMessage))")
                    }
                }
                if t == o.firstMessage.addingTimeInterval(30) {
                    // Also from the reset's side: a reading of the new window (usual since 0.9) would
                    // open the gate on its own and prove nothing about the walk from the reset.
                    let held = store.state.lastExact
                    store.state.lastExact = lastBefore(o.reset) ?? held
                    let open = windowOpen(t)
                    store.state.lastExact = held
                    gateChecks += 1
                    if !open {
                        report.failures.append("probe blocked at \(t), just after a message opened a window")
                    }
                }
                if t == o.firstMessage.addingTimeInterval(60) {
                    // The estimate made from what was known at the reset, before any reading of the
                    // new window: once one exists the meter shows the real reset, which proves nothing.
                    let held = store.state.lastExact
                    store.state.lastExact = lastBefore(o.reset) ?? held
                    let estimated = fiveHour(t)?.resetsAt
                    store.state.lastExact = held
                    guard let estimate = estimated else {
                        openingSkipped += 1 // not calibrated yet
                        continue
                    }
                    openingChecks += 1
                    // The rule the meter goes by: a window opens at its first message rounded down
                    // to 10 minutes. Held to it exactly, so the allowance below can't excuse it.
                    let rounded = Date(timeIntervalSince1970: (o.firstMessage.timeIntervalSince1970 / 600).rounded(.down) * 600)
                    if abs(estimate.timeIntervalSince(rounded.addingTimeInterval(5 * 3600))) > 60 {
                        report.failures.append("window opened by the message at \(o.firstMessage): estimated reset "
                                               + "\(estimate), not its first message rounded down plus 5 hours")
                    }
                    let off = estimate.timeIntervalSince(o.realReset)
                    // A line is written when the reply arrives, so a message logged within a minute
                    // of a 10-minute mark may have reached Anthropic before it, and opened the window
                    // in the slot before. The logs can't tell which (it has gone both ways); the probe
                    // a minute later reads the real reset.
                    let nearMark = o.firstMessage.timeIntervalSince1970.truncatingRemainder(dividingBy: 600) < 60
                    if nearMark, abs(off - 600) <= 60 {
                        openingSlotBefore += 1
                    } else if abs(off) > 60 {
                        report.failures.append("window opened by the message at \(o.firstMessage): "
                                               + "estimated reset \(estimate), real \(o.realReset)")
                    }
                }
            }
        }

        // Early resets: the ones the meter recorded are the ones the readings show.
        let recorded = restarts.map { "\($0.window)@\(Int($0.at.timeIntervalSince1970))" }.sorted()
        let expected = shown.map { "\($0.window)@\(Int($0.at.timeIntervalSince1970))" }.sorted()
        if recorded != expected {
            report.failures.append("early resets: the readings show \(expected.count) (\(expected.joined(separator: ", "))), "
                                   + "the meter recorded \(recorded.count) (\(recorded.joined(separator: ", ")))")
        }

        // Alerts: the same kind and threshold twice for one window is a duplicate, unless Anthropic
        // reset the window early in between, which re-arms them.
        func window(of kind: Substring) -> String? {
            kind == Meter.weeklyTitle ? "week" : kind == Meter.fiveHourTitle || kind == "pace" ? "5h" : nil
        }
        var sent: [String: [(epoch: Double, at: Date)]] = [:]
        var duplicates = 0
        for a in alerts {
            let parts = a.key.split(separator: "|")
            guard parts.count == 3, let epoch = Double(parts[1]) else { continue }
            let kind = "\(parts[0])|\(parts[2])"
            let w = window(of: parts[0])
            if let prior = sent[kind, default: []].last(where: { abs($0.epoch - epoch) < 900 }),
               !shown.contains(where: { $0.window == w && $0.at > prior.at && $0.at <= a.at }) {
                duplicates += 1
                report.failures.append("alert \(a.key) sent twice (again at \(a.at))")
            }
            sent[kind, default: []].append((epoch, a.at))
        }
        // Every threshold alert has a reading behind it (give or take what an estimate can be off): a
        // card that climbed on this Mac's spend alone after Anthropic reset a window would alert on a
        // number nothing measured, as "weekly at 95%" did on Oct 7 when the highest reading was 87%.
        var unbacked = 0
        for a in alerts {
            let parts = a.key.split(separator: "|")
            guard parts.count == 3, let epoch = Double(parts[1]), let threshold = Double(parts[2]), threshold >= 50,
                  parts[0] == Meter.fiveHourTitle || parts[0] == Meter.weeklyTitle else { continue }
            // Readings up to the alert, and the few minutes after it the next reading takes: not one hours
            // later that happened to reach the threshold once real use caught up.
            let measured = readings.filter { $0.at <= a.at.addingTimeInterval(900) }
                .compactMap { parts[0] == Meter.fiveHourTitle ? $0.fiveHour : $0.weekly }
                .filter { Window.same($0.resetsAt, Date(timeIntervalSince1970: epoch)) }
            guard let highest = measured.map(\.pct).max() else {
                unbacked += 1
                report.failures.append("alert \(a.key) sent at \(a.at), but no reading had measured that window by then")
                continue
            }
            guard highest < threshold - 3 else { continue }
            unbacked += 1
            report.failures.append(String(format: "alert %@ sent at %@, but the window's readings never got above %.0f%%",
                                          a.key, "\(a.at)", highest))
        }
        // ...and every alert the dropdown called for went out at least once.
        var missing = 0
        for o in owed {
            let went = alerts.contains { a in
                let parts = a.key.split(separator: "|")
                guard parts.count == 3, String(parts[0]) == o.kind, String(parts[2]) == o.detail,
                      let epoch = Double(parts[1]) else { return false }
                return Window.same(Date(timeIntervalSince1970: epoch), o.resets)
            }
            if !went {
                missing += 1
                report.failures.append("alert \(o.kind) \(o.detail) was called for in the window resetting \(o.resets), and never sent")
            }
        }

        // The "This week" shares can't add up to more than the weekly card says (this Mac's spend is
        // part of it, never more), nor can History draw windows on top of each other, or a window
        // that never reached the cap higher than its readings (it would hold the next one's spend).
        // A capped window's readings stop at 100% while spend goes on, so it is drawn "100%+".
        if let first = shareBreaches.first {
            // By day, so the cause shows: a few steps around a recalibration, or a whole span.
            var perDay: [String: Int] = [:]
            for b in shareBreaches { perDay[String("\(b.at)".prefix(10)), default: 0] += 1 }
            let days = perDay.sorted { $0.key < $1.key }.map { "\($0.key) ×\($0.value)" }.joined(separator: ", ")
            let worst = shareBreaches.max { $0.shares - $0.week < $1.shares - $1.week }!
            report.failures.append(String(format: "\"This week\" shares added up to more than the weekly card at %d steps "
                                          + "(%@); first %@ (%.0f%% of shares against %.0f%% weekly, weekly cap $%.0f), "
                                          + "worst %@ (%.0f%% against %.0f%%, cap $%.0f)",
                                          shareBreaches.count, days, "\(first.at)", first.shares, first.week, first.cap,
                                          "\(worst.at)", worst.shares, worst.week, worst.cap))
        }
        let h = history()
        for (a, b) in zip(h.windows, h.windows.dropFirst()) where b.start < a.end.addingTimeInterval(-60) {
            report.failures.append("History draws the windows \(a.start)–\(a.end) and \(b.start)–\(b.end) on top of each other")
        }
        // Each window's readings were taken while it was open, so some drawn window spans them all.
        var groups: [(first: Date, last: Date, reset: Date)] = []
        for r in readings {
            guard let w = r.fiveHour else { continue }
            if let i = groups.lastIndex(where: { Window.same($0.reset, w.resetsAt) }) {
                groups[i].last = r.at
            } else {
                groups.append((r.at, r.at, w.resetsAt))
            }
        }
        let drawnSince = clock().addingTimeInterval(-7 * 86400)
        for g in groups where g.reset > drawnSince.addingTimeInterval(3600) {
            let spanned = h.windows.contains { $0.start <= g.first.addingTimeInterval(60) && $0.end >= g.last.addingTimeInterval(-60) }
            if !spanned {
                report.failures.append("History has no window spanning the readings of the one resetting \(g.reset) "
                                       + "(\(g.first) to \(g.last))")
            }
        }
        // A drawn window holds only readings of its own 5 hours: one that has another window's
        // readings inside it (an early reset it wasn't cut at) is drawn too long.
        // One exact-backed window for each group of readings, no more: the early reset's window is its
        // own, not pinned to the one it cut short (which would draw a third, and count a cap twice).
        let groupsDrawn = groups.filter { $0.reset > drawnSince.addingTimeInterval(6 * 3600) }.count
        let exactDrawn = h.windows.filter { $0.exact && $0.end > drawnSince.addingTimeInterval(6 * 3600) }.count
        if exactDrawn != groupsDrawn {
            report.failures.append("History draws \(exactDrawn) windows backed by readings; the readings are of \(groupsDrawn)")
        }
        var strangers = 0
        for x in h.windows {
            for r in readings {
                guard let w = r.fiveHour, r.at > x.start.addingTimeInterval(60), r.at < x.end.addingTimeInterval(-60) else { continue }
                if x.start < w.resetsAt.addingTimeInterval(-5 * 3600 - 900) || x.end > w.resetsAt.addingTimeInterval(900) {
                    strangers += 1
                    if strangers == 1 {
                        report.failures.append("History draws \(x.start)–\(x.end) around a reading at \(r.at) of the window resetting "
                                               + "\(w.resetsAt), which doesn't fit inside it")
                    }
                    break
                }
            }
        }
        if strangers > 1 { report.failures.append("...and \(strangers - 1) more windows like it") }
        for w in h.windows where w.exact {
            // Its own readings: the ones whose reset falls where this window's 5 hours end.
            let seen = readings.compactMap(\.fiveHour)
                .filter { $0.resetsAt > w.start.addingTimeInterval(4.75 * 3600) && $0.resetsAt <= w.start.addingTimeInterval(5.25 * 3600) }
                .map(\.pct)
            if let top = seen.max(), top < 99, w.peak > top + 10 {
                report.failures.append(String(format: "History peaks the window from %@ at %.0f%% but its readings reached %.0f%%",
                                              "\(w.start)", w.peak, top))
            }
        }

        let span = String(format: "%.1f", end.timeIntervalSince(start) / 86400)
        report.lines.append("Replayed \(readings.count) exact readings over \(span) days, \(all.count) logged turns, \(times.count) steps.")
        report.lines.append("1. Window openings: \(openingChecks) checked (\(openingSlotBefore) opened the slot before, "
                            + "message logged just past a mark), \(openingSkipped) skipped before calibration, "
                            + "\(openingsMoved) moved by an early reset, \(openingsForeign) opened away from this Mac.")
        report.lines.append("2. Probe gate: \(gateChecks) points checked.")
        report.lines.append("3. Alerts: \(alerts.count) sent, \(duplicates) duplicate, \(unbacked) unbacked by a reading, \(missing) missing of \(owed.count) called for"
                            + (restarts.isEmpty ? "." : ", across \(restarts.count) early reset\(restarts.count == 1 ? "" : "s") (\(restarts.map(\.window).joined(separator: ", "))) that re-arm them."))
        // The floors in full from three days of readings on; a newer install, with less to replay, is held
        // to its share of them rather than failing for history it doesn't have yet.
        let history = min(1, end.timeIntervalSince(start) / (3 * 86400))
        // At least one of each, however short: a run that checked nothing proves nothing.
        func floor(_ full: Int) -> Int { max(1, Int(Double(full) * history)) }
        if openingChecks < floor(Replay.minimum.openings) || openingSkipped > openingChecks {
            report.failures.append("only \(openingChecks) window openings checked (\(openingSkipped) skipped), "
                                   + "need \(floor(Replay.minimum.openings))")
        }
        if gateChecks < floor(Replay.minimum.gate) {
            report.failures.append("only \(gateChecks) probe gate points checked, need \(floor(Replay.minimum.gate))")
        }
        let checks = store.state.checks ?? []
        if accuracyUnscored > 0 {
            report.lines.append("   \(accuracyUnscored) estimates had the wrong window and went unscored.")
            // A few are an early reset caught between readings; many are estimates drawing the wrong
            // window, which scoring only the rest would hide.
            let attempts = accuracyUnscored + checks.count
            if accuracyUnscored >= 3, Double(accuracyUnscored) > 0.1 * Double(attempts) {
                report.failures.append("\(accuracyUnscored) of \(attempts) estimates had the wrong window (over 10%)")
            }
        }
        // The logs reach back 8 days, so only a week that began inside them can teach the weekly cap:
        // just after a rollover there is little or nothing to check, and demanding the full count then
        // would fail a meter that is fine. The weekly floor follows how long the readings it could learn
        // from span: the full count from half a week on, none below a day's worth (too few to judge by).
        let weeklyReplayable = readings.filter { r in
            guard let w = r.weekly else { return false }
            return w.pct >= 5 && w.restartedLate != true && w.resetsAt.addingTimeInterval(-7 * 86400) >= coveredFrom
        }
        let weeklySpan = (weeklyReplayable.last?.at).map { $0.timeIntervalSince(weeklyReplayable[0].at) } ?? 0
        let weeklyNeed = min(Replay.minimum.accuracy, Int(Double(Replay.minimum.accuracy) * weeklySpan / (3.5 * 86400)))
        for (window, name, bar) in [("5h", "5-hour", Replay.accuracyBar.fiveHour), ("week", "weekly", Replay.accuracyBar.weekly)] {
            let errors = checks.filter { $0.window == window }.map { $0.estimated - $0.exact }
            let need = window == "week" ? (weeklyNeed < 8 ? 0 : weeklyNeed) : floor(Replay.minimum.accuracy)
            if need == 0, errors.count < 8 {
                report.lines.append("4. Accuracy, \(name): \(errors.count) checks, too few to judge (the week began too recently for the logs to teach its cap)")
                continue
            }
            guard errors.count >= need else {
                report.lines.append("4. Accuracy, \(name): \(errors.count) checks")
                report.failures.append("only \(errors.count) \(name) accuracy checks, need \(need)")
                continue
            }
            let typical = errors.map(abs).reduce(0, +) / Double(errors.count)
            let bias = errors.reduce(0, +) / Double(errors.count)
            let worst = errors.max { abs($0) < abs($1) } ?? 0
            // How much the estimate grew over what the reading says it grew, summed over every check:
            // 1.00 is a right cap. A wrong one shows here even where the points are too few to move the
            // typical error (the weekly climbs about a point an hour).
            let mine = checks.filter { $0.window == window }
            let measuredGrowth = mine.reduce(0) { $0 + ($1.exact - ($1.anchor ?? $1.exact)) }
            let estimatedGrowth = mine.reduce(0) { $0 + ($1.estimated - ($1.anchor ?? $1.exact)) }
            let growth = measuredGrowth > 0 ? estimatedGrowth / measuredGrowth : 1
            report.lines.append(String(format: "4. Accuracy, %@: ±%.2f typical over %d checks (bias %+.2f, worst %+.1f), bar ±%.1f; growth %.2f× what was measured",
                                       name, typical, errors.count, bias, worst, bar, growth))
            // (Only with enough measured growth to judge by: a few points are mostly rounding.)
            if measuredGrowth >= 5, abs(growth - 1) > Replay.growthBar {
                report.failures.append(String(format: "%@ estimates grew %.2f× what the readings measured, outside 1 ± %.2f (a wrong cap)",
                                              name, growth, Replay.growthBar))
            }
            if typical > bar {
                report.failures.append(String(format: "%@ estimates typically off by ±%.2f, over the ±%.1f bar", name, typical, bar))
            }
        }
        syntheticChecks(&report)
        return report
    }

    /// 6. Made-up cases the history log may never hold, run on this meter once the replay is done:
    /// the pace and chart after an early reset count only the spend since it, a window that lapsed
    /// since its last reading is stale and raises no threshold alert, the probe gate keeps clear of a
    /// walked window's reset, and a reading's open window is probed with nothing logged here.
    /// Set at a moment long before any real history, so nothing in the history log falls near it.
    private func syntheticChecks(_ report: inout ReplayReport) {
        let heldTurns = turns, heldState = store.state, heldClock = clock, heldCovered = coveredFrom
        defer {
            turns = heldTurns
            store.state = heldState
            clock = heldClock
            coveredFrom = heldCovered
        }
        coveredFrom = .distantPast
        let mark = Date(timeIntervalSince1970: 999_999_600) // on a 10-minute mark
        // $15 a turn at 1M output tokens (Sonnet 4.5), $0.15 at 10k.
        func turn(_ at: Date, output: Int) -> Turn {
            Turn(key: "synthetic-\(Int(at.timeIntervalSince1970))", at: at, project: "synthetic", model: "claude-sonnet-4-5",
                 session: "synthetic", input: 0, output: output, cacheRead: 0, write5m: 0, write1h: 0, fast: false)
        }
        func setUp(now: Date, turns made: [Turn], reading: ExactReading?, cap5h: Double?, capWeek: Double?) {
            clock = { now }
            turns = made.sorted { $0.at < $1.at }
            var state = PersistedState()
            state.lastExact = reading
            state.calibration.cap5h = cap5h
            state.calibration.capWeek = capWeek
            store.state = state
        }
        var ran = 0
        func expect(_ ok: Bool, _ failure: String) {
            ran += 1
            if !ok { report.failures.append("synthetic: " + failure) }
        }

        // An early 5-hour reset 30 minutes ago, after $30 of spend (the whole cap) that no longer counts.
        var now = mark.addingTimeInterval(3 * 3600)
        var restart = now.addingTimeInterval(-1800)
        setUp(now: now,
              turns: [turn(now.addingTimeInterval(-2400), output: 1_000_000), turn(now.addingTimeInterval(-2100), output: 1_000_000),
                      turn(now.addingTimeInterval(-600), output: 10_000)],
              reading: ExactReading(at: now.addingTimeInterval(-60), source: "probe",
                                    fiveHour: Window(pct: 2, resetsAt: now.addingTimeInterval(2 * 3600),
                                                     at: now.addingTimeInterval(-60), restartedAt: restart)),
              cap5h: 30, capWeek: nil)
        recompute()
        if let f = snapshot.fiveHour {
            expect(f.capAt == nil && (f.atReset ?? 0) < 100,
                   "5-hour pace after an early reset counts the spend before it (lands at \(f.atReset ?? -1)%)")
            let charted = f.series.filter { $0.at < restart }.map(\.pct).max() ?? 0
            expect(charted == 0, "5-hour chart after an early reset climbs to \(charted)% before it")
        } else {
            expect(false, "no 5-hour card for a window open after an early reset")
        }

        // An early weekly reset 3 hours ago, after $30 of spend (the whole cap) that no longer counts.
        restart = now.addingTimeInterval(-3 * 3600)
        setUp(now: now,
              turns: [turn(now.addingTimeInterval(-5 * 3600), output: 1_000_000), turn(now.addingTimeInterval(-4 * 3600), output: 1_000_000),
                      turn(now.addingTimeInterval(-3600), output: 10_000)],
              reading: ExactReading(at: now.addingTimeInterval(-60), source: "probe",
                                    weekly: Window(pct: 1, resetsAt: now.addingTimeInterval(3 * 86400),
                                                   at: now.addingTimeInterval(-60), restartedAt: restart)),
              cap5h: nil, capWeek: 30)
        recompute()
        if let w = snapshot.weekly {
            expect(w.capAt == nil && (w.atReset ?? 0) < 100,
                   "weekly pace after an early reset counts the spend before it (lands at \(w.atReset ?? -1)%)")
        } else {
            expect(false, "no weekly card for a week open after an early reset")
        }

        // Both windows lapsed an hour ago (the Mac slept across the resets); $15 logged since, past both caps.
        setUp(now: now,
              turns: [turn(now.addingTimeInterval(-1200), output: 1_000_000)],
              reading: ExactReading(at: now.addingTimeInterval(-4200), source: "probe",
                                    fiveHour: Window(pct: 50, resetsAt: now.addingTimeInterval(-3600), at: now.addingTimeInterval(-4200)),
                                    weekly: Window(pct: 50, resetsAt: now.addingTimeInterval(-3600), at: now.addingTimeInterval(-4200))),
              cap5h: 10, capWeek: 10)
        recompute()
        let lapsed = [snapshot.fiveHour, snapshot.weekly].compactMap { $0 }
        expect(lapsed.count == 2 && lapsed.allSatisfy { $0.stale && !$0.idle },
               "a window lapsed since its last reading isn't marked stale")
        var keys: [String] = []
        let notifier = Notifier(store: store) { keys.append($0) }
        notifier.check(snapshot, now: now, post: true)
        let thresholds = keys.filter { $0.hasPrefix(Meter.fiveHourTitle + "|") || $0.hasPrefix(Meter.weeklyTitle + "|") }
        expect(thresholds.isEmpty, "a lapsed window nothing has measured raised \(thresholds.joined(separator: ", "))")

        // The probe gate near the end of a window walked from a message (none of it measured).
        setUp(now: mark,
              turns: [turn(mark.addingTimeInterval(30), output: 10_000)],
              reading: ExactReading(at: mark.addingTimeInterval(-7200), source: "probe",
                                    fiveHour: Window(pct: 10, resetsAt: mark.addingTimeInterval(-3600), at: mark.addingTimeInterval(-7200))),
              cap5h: 10, capWeek: nil)
        expect(windowOpen(mark.addingTimeInterval(4 * 3600)), "probe blocked inside a window walked from a message")
        expect(!windowOpen(mark.addingTimeInterval(5 * 3600 - 60)),
               "probe would run a minute before a walked window's reset, and could open the next one")

        // Use only away from this Mac: the reading's window is open, nothing is logged here.
        now = mark
        setUp(now: now, turns: [],
              reading: ExactReading(at: now.addingTimeInterval(-120), source: "probe",
                                    fiveHour: Window(pct: 10, resetsAt: now.addingTimeInterval(3600), at: now.addingTimeInterval(-120))),
              cap5h: nil, capWeek: nil)
        expect(windowOpen(now), "no probe while the last reading's window is open, with nothing logged on this Mac")

        // A window opened away from this Mac after the last reading's ended: the usage report lists it.
        setUp(now: now, turns: [],
              reading: ExactReading(at: now.addingTimeInterval(-7200), source: "probe",
                                    fiveHour: Window(pct: 66, resetsAt: now.addingTimeInterval(-1800), at: now.addingTimeInterval(-7200))),
              cap5h: nil, capWeek: nil)
        expect(!windowOpen(now), "probe allowed with no window open anywhere")
        store.state.sessionResets = now.addingTimeInterval(4 * 3600)
        expect(windowOpen(now), "no probe in a window the usage report lists, opened away from this Mac")
        expect(!windowOpen(now.addingTimeInterval(4 * 3600 - 60)),
               "probe would run a minute before the report's window resets, and could open the next one")
        // A report listing the reading's own window adds nothing once that window has ended.
        store.state.sessionResets = now.addingTimeInterval(-1800)
        expect(!windowOpen(now), "an ended window from the usage report let a probe through")

        report.lines.append("6. Synthetic: \(ran) checks (early-reset pace and chart, lapsed windows, probe gate).")
    }

    /// The history log saves each reading as the meter held it, windows carried over from earlier
    /// readings included (a probe can leave one out: past the 5-hour cap it stopped reporting the
    /// weekly). Replayed as they are, those would count as new measurements of a stale number.
    private static func measuredOnly(_ r: ExactReading) -> ExactReading {
        var r = r
        let own = Meter.measured(by: r)
        if !own.contains("5h") { r.fiveHour = nil }
        if !own.contains("week") { r.weekly = nil }
        let at = r.at
        r.extras = r.extras.filter { abs(($0.value.at ?? at).timeIntervalSince(at)) < 1 }
        return r
    }
}
