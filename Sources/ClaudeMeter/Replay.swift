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

        // Every logged turn, read once; at each step the meter is handed those up to its clock.
        let index = LogIndex()
        index.loadCache()
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
        var shown: [(at: Date, window: String)] = []
        var heldWindow: [String: Window] = [:]
        for r in readings where r.source != "tap" {
            for (name, w, span) in [("5h", r.fiveHour, 5 * 3600.0), ("week", r.weekly, 7 * 86400.0)] {
                guard let w else { continue }
                if let held = heldWindow[name] {
                    if w.resetsAt < held.resetsAt.addingTimeInterval(-900) { continue }
                    if Window.same(held.resetsAt, w.resetsAt) {
                        if w.pct < held.pct - 0.5 { shown.append((r.at, name)) }
                    } else if w.resetsAt.addingTimeInterval(-span) < held.resetsAt.addingTimeInterval(-60) {
                        shown.append((r.at, name)) // a later window that began before the held one was due
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

            for w in [snapshot.fiveHour, snapshot.weekly].compactMap({ $0 }) where !w.idle {
                guard let r = w.resetsAt else { continue }
                for threshold in [80.0, 95.0] where w.pct >= threshold { owe(w.title, "\(Int(threshold))", r) }
            }
            if let f = snapshot.fiveHour, let r = f.resetsAt {
                if let capAt = f.capAt, snapshot.capWarning != nil {
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
        report.lines.append("3. Alerts: \(alerts.count) sent, \(duplicates) duplicate, \(missing) missing of \(owed.count) called for"
                            + (restarts.isEmpty ? "." : ", across \(restarts.count) early reset\(restarts.count == 1 ? "" : "s") (\(restarts.map(\.window).joined(separator: ", "))) that re-arm them."))
        if openingChecks < Replay.minimum.openings || openingSkipped > openingChecks {
            report.failures.append("only \(openingChecks) window openings checked (\(openingSkipped) skipped), "
                                   + "need \(Replay.minimum.openings)")
        }
        if gateChecks < Replay.minimum.gate {
            report.failures.append("only \(gateChecks) probe gate points checked, need \(Replay.minimum.gate)")
        }
        if accuracyUnscored > 0 {
            report.lines.append("   \(accuracyUnscored) estimates had the wrong window and went unscored.")
        }
        let checks = store.state.checks ?? []
        for (window, name, bar) in [("5h", "5-hour", Replay.accuracyBar.fiveHour), ("week", "weekly", Replay.accuracyBar.weekly)] {
            let errors = checks.filter { $0.window == window }.map { $0.estimated - $0.exact }
            guard errors.count >= Replay.minimum.accuracy else {
                report.lines.append("4. Accuracy, \(name): \(errors.count) checks")
                report.failures.append("only \(errors.count) \(name) accuracy checks, need \(Replay.minimum.accuracy)")
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
            if abs(growth - 1) > Replay.growthBar {
                report.failures.append(String(format: "%@ estimates grew %.2f× what the readings measured, outside 1 ± %.2f (a wrong cap)",
                                              name, growth, Replay.growthBar))
            }
            if typical > bar {
                report.failures.append(String(format: "%@ estimates typically off by ±%.2f, over the ±%.1f bar", name, typical, bar))
            }
        }
        return report
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
