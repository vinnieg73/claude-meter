import Foundation

/// `ClaudeMeter --replay`: steps the real meter code through this Mac's history log and
/// transcripts with a moving clock, from a blank state (calibration is learned along the way),
/// and checks what has to hold. Reads, never writes. Exits non-zero on any failure.
///
/// 1. Window openings: after each reset, the meter's estimate of the next window's reset
///    matches the real one (from the history log) within a minute.
/// 2. Probe gate: between a reset and the next message, a probe would not run (it would open
///    a window); right after that message it would.
/// 3. Alerts: none goes out twice for the same window.
/// 4. Accuracy: estimates made just before each exact reading are within the bar.
@MainActor
enum Replay {
    /// Typical (mean absolute) error allowed, in points.
    static let accuracyBar = (fiveHour: 1.5, weekly: 1.0)

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

        // Every logged turn, read once; at each step the meter is handed those up to its clock.
        let index = LogIndex()
        index.loadCache()
        index.refresh()
        let all = index.turns
        guard let firstTurn = all.first?.at else {
            report.failures.append("no Claude Code transcripts to replay")
            return report
        }
        // Only readings whose windows the logs cover.
        let readings = HistoryLog.load().readings
            .filter { $0.at > firstTurn.addingTimeInterval(5 * 3600) }
            .sorted { $0.at < $1.at }
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
        for (reset, next) in zip(resets, resets.dropFirst()) {
            let i = upTo(reset)
            guard i < all.count else { continue }
            let first = all[i].at
            // Only when the next recorded window is the one this message opened.
            guard next.addingTimeInterval(-5 * 3600) <= first, first < next else { continue }
            openings.append(Opening(reset: reset, firstMessage: first, realReset: next))
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
        let notifier = Notifier(store: store) { [unowned self] key in alerts.append((self.clock(), key)) }
        var gateChecks = 0, openingChecks = 0, openingSkipped = 0
        var next = 0
        loaded = true
        for t in times.sorted() {
            clock = { t }
            turns = Array(all[..<upTo(t)])
            while next < readings.count, readings[next].at <= t {
                absorb(readings[next])
                next += 1
            }
            recompute()
            notifier.check(snapshot, now: t, post: true)

            for o in openings {
                if t == o.reset.addingTimeInterval(30), o.firstMessage > o.reset.addingTimeInterval(60) {
                    // Judged from what the meter knew at the reset: a reading taken since then may be
                    // the old probe's (pre-0.8 it ran seconds after a reset and opened the window
                    // itself), and this code wouldn't have taken it.
                    let held = store.state.lastExact
                    store.state.lastExact = readings.last { $0.at <= o.reset } ?? held
                    let open = windowOpen(t)
                    store.state.lastExact = held
                    gateChecks += 1
                    if open {
                        report.failures.append("probe would run at \(t) with no window open "
                                               + "(reset \(o.reset), next message \(o.firstMessage))")
                    }
                }
                if t == o.firstMessage.addingTimeInterval(30) {
                    gateChecks += 1
                    if !windowOpen(t) {
                        report.failures.append("probe blocked at \(t), just after a message opened a window")
                    }
                }
                if t == o.firstMessage.addingTimeInterval(60) {
                    // The estimate made from what was known at the reset, before any reading of the
                    // new window: once one exists the meter shows the real reset, which proves nothing.
                    let held = store.state.lastExact
                    store.state.lastExact = readings.last { $0.at <= o.reset } ?? held
                    let estimated = fiveHour(t)?.resetsAt
                    store.state.lastExact = held
                    guard let estimate = estimated else {
                        openingSkipped += 1 // not calibrated yet
                        continue
                    }
                    openingChecks += 1
                    if abs(estimate.timeIntervalSince(o.realReset)) > 60 {
                        report.failures.append("window opened by the message at \(o.firstMessage): "
                                               + "estimated reset \(estimate), real \(o.realReset)")
                    }
                }
            }
        }

        // Alerts: the same kind and threshold twice for one window is a duplicate.
        var sent: [String: [Double]] = [:]
        var duplicates = 0
        for a in alerts {
            let parts = a.key.split(separator: "|")
            guard parts.count == 3, let epoch = Double(parts[1]) else { continue }
            let kind = "\(parts[0])|\(parts[2])"
            if sent[kind, default: []].contains(where: { abs($0 - epoch) < 900 }) {
                duplicates += 1
                report.failures.append("alert \(a.key) sent twice (again at \(a.at))")
            }
            sent[kind, default: []].append(epoch)
        }

        let span = String(format: "%.1f", end.timeIntervalSince(start) / 86400)
        report.lines.append("Replayed \(readings.count) exact readings over \(span) days, \(all.count) logged turns, \(times.count) steps.")
        report.lines.append("1. Window openings: \(openingChecks) checked, \(openingSkipped) skipped before calibration.")
        report.lines.append("2. Probe gate: \(gateChecks) points checked.")
        report.lines.append("3. Alerts: \(alerts.count) sent, \(duplicates) duplicate.")
        let checks = store.state.checks ?? []
        for (window, name, bar) in [("5h", "5-hour", Replay.accuracyBar.fiveHour), ("week", "weekly", Replay.accuracyBar.weekly)] {
            let errors = checks.filter { $0.window == window }.map { $0.estimated - $0.exact }
            guard !errors.isEmpty else {
                report.lines.append("4. Accuracy, \(name): no checks")
                continue
            }
            let typical = errors.map(abs).reduce(0, +) / Double(errors.count)
            let bias = errors.reduce(0, +) / Double(errors.count)
            let worst = errors.max { abs($0) < abs($1) } ?? 0
            report.lines.append(String(format: "4. Accuracy, %@: ±%.2f typical over %d checks (bias %+.2f, worst %+.1f), bar ±%.1f",
                                       name, typical, errors.count, bias, worst, bar))
            if typical > bar {
                report.failures.append(String(format: "%@ estimates typically off by ±%.2f, over the ±%.1f bar", name, typical, bar))
            }
        }
        return report
    }
}
