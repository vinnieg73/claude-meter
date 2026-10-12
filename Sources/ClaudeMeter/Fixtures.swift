import Foundation

/// Made-up states for `--render --fixture <name>`, so every look of the dropdown and History can
/// be checked without waiting for it to happen. Times are relative to now. Nothing here is read
/// by the running app.
@MainActor
enum Fixtures {
    static let popover = ["calm", "warn", "critical", "idle", "empty", "loading", "trouble", "week", "long", "nofable"]
    static let history = ["fits", "uncalibrated"]

    /// `weekScope` is the Today / This week picker; `notice` stands in for the meter's own.
    struct Popover {
        var snapshot: Snapshot
        var weekScope = false
        var notice: String?
    }

    static func popover(_ name: String) -> Popover? {
        switch name {
        case "calm": calm
        case "warn": warn
        case "critical": critical
        case "idle": idle
        case "empty": empty
        case "loading": Popover(snapshot: Snapshot())
        case "trouble": trouble
        case "week": week
        case "long": long
        case "nofable": nofable
        default: nil
        }
    }

    static func history(_ name: String) -> History? {
        switch name {
        case "fits": fits
        case "uncalibrated": uncalibrated
        default: nil
        }
    }

    // MARK: - Building blocks

    private static var now: Date { Date() }

    /// A bursty climb from 0 to `to`, over `from`...now.
    private static func climb(from start: Date, to pct: Double, until end: Date = Date()) -> [PacePoint] {
        let steps: [Double] = [0, 3, 2, 8, 6, 1, 0, 4, 9, 5, 2, 7, 10, 3, 6, 4]
        let total = steps.reduce(0, +)
        var used = 0.0
        return steps.enumerated().map { i, step in
            used += step
            let at = start.addingTimeInterval(end.timeIntervalSince(start) * Double(i) / Double(steps.count - 1))
            return PacePoint(at: at, pct: used / total * pct)
        }
    }

    private static func fiveHour(_ pct: Double, left: TimeInterval, exact: Bool = false, landing: Double? = nil,
                                 capIn: TimeInterval? = nil) -> WindowView {
        let resets = now.addingTimeInterval(left)
        let start = resets.addingTimeInterval(-5 * 3600)
        var w = WindowView(title: "5-hour window", pct: pct, resetsAt: resets, exact: exact,
                           asOf: now.addingTimeInterval(exact ? -120 : -180))
        w.start = start
        w.series = climb(from: start, to: pct)
        if !exact {
            w.accuracy = "±1.0"
            w.accuracyDetail = "Estimates have been within ±1.0 pts over 20 checks."
        }
        if let capIn {
            let capAt = now.addingTimeInterval(capIn)
            w.capAt = capAt
            w.projection = "At this pace: capped at \(Fmt.when(capAt))"
            w.projectionWarn = true
            w.pace = [PacePoint(at: now, pct: pct), PacePoint(at: capAt, pct: 100)]
        } else if let landing {
            w.atReset = landing
            w.projection = "At this pace: ~\(Fmt.pct(landing)) by reset"
            w.pace = [PacePoint(at: now, pct: pct), PacePoint(at: resets, pct: landing)]
        }
        return w
    }

    private static func weekly(_ pct: Double, left: TimeInterval, exact: Bool = false, landing: Double,
                               projection: String, projectionWarn: Bool = false, budget: String,
                               budgetWarn: Bool = false) -> WindowView {
        var w = WindowView(title: "Weekly · all models", pct: pct, resetsAt: now.addingTimeInterval(left),
                           exact: exact, asOf: now.addingTimeInterval(exact ? -120 : -180))
        if !exact {
            w.accuracy = "±0.3"
            w.accuracyDetail = "Estimates have been within ±0.3 pts over 20 checks."
        }
        w.averageAtReset = landing
        w.projection = projection
        w.projectionWarn = projectionWarn
        w.budget = budget
        w.budgetWarn = budgetWarn
        return w
    }

    /// The Fable limit as the usage report gave it: exact, read 4 minutes ago.
    private static func fable(_ pct: Double, left: TimeInterval) -> WindowView {
        WindowView(title: Meter.fableTitle, pct: pct, resetsAt: now.addingTimeInterval(left), exact: true,
                   asOf: now.addingTimeInterval(-240))
    }

    private static func days(_ costs: [Double]) -> [DayBar] {
        let today = Calendar.current.startOfDay(for: now)
        return costs.enumerated().map { i, cost in
            DayBar(day: Calendar.current.date(byAdding: .day, value: i - (costs.count - 1), to: today)!, cost: cost)
        }
    }

    private static func base(_ level: Level, title: String, pct: Double) -> Snapshot {
        var s = Snapshot()
        s.loaded = true
        s.calibrated = true
        s.hasReading = true
        s.tapSeen = now.addingTimeInterval(-240)
        s.menuTitle = title
        s.menuPct = pct
        s.level = level
        return s
    }

    // MARK: - Dropdown states

    private static var calm: Popover {
        var s = base(.normal, title: "34% · 2h50m", pct: 34)
        s.fiveHour = fiveHour(34, left: 2.83 * 3600, exact: true, landing: 48)
        s.weekly = weekly(41, left: 3.2 * 86400, landing: 78, projection: "7-day pace: ~78% at reset · today's: ~70%",
                          budget: "Budget ~18%/day to the reset · 7-day average 11%/day")
        s.fable = FableView(limit: fable(7, left: 3.2 * 86400), fiveHourCost: 1.1, fiveHourPts: 2.8,
                            weekCost: 6.2, weekTokens: 2_300_000, weekPts: 0.9, todayCost: 2.2)
        s.burning = [Burn(id: "a", name: "Claude Meter", model: "Fable 5.1", perHour: 4.12, pctPerHour: 2.5, fable: true)]
        s.activeCount = 1
        s.todayCost = 21.4
        s.todayTokens = 48_000_000
        s.cacheHit = 0.96
        s.projects = [Row(id: "Claude Meter", cost: 14.2, tokens: 0), Row(id: "Pocket Saloon", cost: 6.9, tokens: 0),
                      Row(id: "Five Card Poker", cost: 0.3, tokens: 0)]
        s.models = [Row(id: "Opus 5.5", cost: 18.7, tokens: 0), Row(id: "Fable 5.1", cost: 2.2, tokens: 0),
                    Row(id: "Haiku 4.5", cost: 0.5, tokens: 0)]
        s.daily = days([88, 140, 52, 12, 0, 96, 21.4])
        return Popover(snapshot: s)
    }

    private static var warn: Popover {
        var s = base(.warn, title: "~78% · 1h10m", pct: 78)
        s.fiveHour = fiveHour(78, left: 70 * 60, landing: 96)
        s.weekly = weekly(73, left: 16.3 * 3600, landing: 80, projection: "7-day pace: ~80% at reset · today's: ~84%",
                          budget: "Budget ~40%/day to the reset · 7-day average 11%/day")
        s.fable = FableView(limit: fable(74, left: 16.3 * 3600), fiveHourCost: 0, fiveHourPts: 0,
                            weekCost: 212, weekTokens: 180_000_000, weekPts: 14, todayCost: 0)
        s.burning = [
            Burn(id: "a", name: "Pocket Saloon", model: "Opus 5.5", perHour: 8.71, pctPerHour: 5.3),
            Burn(id: "b", name: "Frontier Universe", model: "Opus 5.5", perHour: 6.54, pctPerHour: 4.0),
            Burn(id: "c", name: "Claude Meter", model: "Sonnet 5.5", perHour: 1.20, pctPerHour: 0.7),
        ]
        s.cooling = [
            Cooling(id: "d", name: "Five Card Poker", coldAt: now.addingTimeInterval(6 * 60), extra: 1.00, extraPct: 0.6),
            Cooling(id: "e", name: "Pocket Saloon", coldAt: now.addingTimeInterval(39 * 60), extra: 5.75, extraPct: 3.5),
        ]
        s.activeCount = 4
        s.todayCost = 139
        s.todayTokens = 396_000_000
        s.cacheHit = 0.98
        s.projects = [Row(id: "Pocket Saloon", cost: 125, tokens: 0), Row(id: "Claude Meter", cost: 8.85, tokens: 0),
                      Row(id: "Frontier Universe", cost: 4.66, tokens: 0), Row(id: "Five Card Poker", cost: 0.5, tokens: 0)]
        s.models = [Row(id: "Opus 5.5", cost: 138, tokens: 0), Row(id: "Sonnet 5.5", cost: 0.36, tokens: 0),
                    Row(id: "Haiku 4.5", cost: 0.07, tokens: 0)]
        s.daily = days([310, 28, 140, 22, 25, 72, 139])
        return Popover(snapshot: s)
    }

    private static var critical: Popover {
        var s = base(.critical, title: "~94% · cap \(Fmt.when(Date().addingTimeInterval(14 * 60)))", pct: 94)
        s.fiveHour = fiveHour(94, left: 55 * 60, capIn: 14 * 60)
        s.capWarning = now.addingTimeInterval(14 * 60)
        s.weekly = weekly(91, left: 1.6 * 86400, landing: 112,
                          projection: "7-day pace: out \(Fmt.when(Date().addingTimeInterval(20 * 3600))) · today's: out \(Fmt.when(Date().addingTimeInterval(6 * 3600)))",
                          projectionWarn: true,
                          budget: "Budget ~5.6%/day to the reset · 7-day average 13%/day", budgetWarn: true)
        s.extras = [
            WindowView(title: "Weekly · Opus", pct: 88, resetsAt: now.addingTimeInterval(1.6 * 86400), exact: false,
                       asOf: now.addingTimeInterval(-600)),
            WindowView(title: "Weekly · Sonnet", pct: 12, resetsAt: now.addingTimeInterval(1.6 * 86400), exact: false,
                       asOf: now.addingTimeInterval(-3 * 3600)),
        ]
        s.burning = [
            Burn(id: "a", name: "Frontier Universe", model: "Opus 5.5", perHour: 48.2, pctPerHour: 29),
            Burn(id: "b", name: "Pocket Saloon", model: "Opus 5.5", perHour: 9.1, pctPerHour: 5.5),
            Burn(id: "c", name: "Pocket Saloon", model: "Opus 5.5", perHour: 6.5, pctPerHour: 3.9),
            Burn(id: "f", name: "Claude Meter", model: "Fable 5.1", perHour: 3.2, pctPerHour: 1.9, fable: true),
        ]
        s.fable = FableView(limit: fable(92, left: 1.6 * 86400), fiveHourCost: 6.2, fiveHourPts: 3.7,
                            weekCost: 318, weekTokens: 260_000_000, weekPts: 21, todayCost: 6.2)
        s.runaways = [Runaway(id: "a", name: "Frontier Universe", pct: 23)]
        s.cooling = [
            Cooling(id: "d", name: "Five Card Poker", coldAt: now.addingTimeInterval(4 * 60), extra: 1.00, extraPct: 0.6),
            Cooling(id: "e", name: "Pocket Saloon", coldAt: now.addingTimeInterval(21 * 60), extra: 5.75, extraPct: 3.5),
            Cooling(id: "g", name: "Claude Meter", coldAt: now.addingTimeInterval(52 * 60), extra: 2.10, extraPct: 1.3),
        ]
        s.activeCount = 6
        s.todayCost = 212
        s.todayTokens = 610_000_000
        s.cacheHit = 0.97
        s.projects = [Row(id: "Frontier Universe", cost: 120, tokens: 0), Row(id: "Pocket Saloon", cost: 80, tokens: 0),
                      Row(id: "Claude Meter", cost: 11, tokens: 0), Row(id: "Five Card Poker", cost: 1, tokens: 0)]
        s.models = [Row(id: "Opus 5.5", cost: 205, tokens: 0), Row(id: "Fable 5.1", cost: 6.2, tokens: 0),
                    Row(id: "Haiku 4.5", cost: 0.8, tokens: 0)]
        s.daily = days([180, 240, 160, 30, 90, 260, 212])
        return Popover(snapshot: s)
    }

    private static var idle: Popover {
        var s = base(.normal, title: "~0%", pct: 0) // an estimated 0%: no window is open
        s.fiveHour = WindowView(title: "5-hour window", pct: 0, exact: false, asOf: now.addingTimeInterval(-6 * 3600),
                                idle: true)
        s.weekly = weekly(22, left: 5.1 * 86400, exact: true, landing: 51, projection: "7-day pace: ~51% at reset",
                          budget: "Budget ~15%/day to the reset · 7-day average 6.4%/day")
        s.fable = FableView(limit: fable(0, left: 5.1 * 86400), weekCost: 0, weekPts: 0)
        s.todayCost = 3.1
        s.todayTokens = 6_200_000
        s.cacheHit = 0.91
        s.projects = [Row(id: "Claude Meter", cost: 3.1, tokens: 0)]
        s.models = [Row(id: "Opus 5.5", cost: 3.1, tokens: 0)]
        s.daily = days([40, 0, 12, 66, 18, 0, 3.1])
        return Popover(snapshot: s)
    }

    private static var empty: Popover {
        var s = Snapshot()
        s.loaded = true
        s.menuTitle = "$0.42 today"
        s.todayCost = 0.42
        s.todayTokens = 310_000
        s.projects = [Row(id: "Claude Meter", cost: 0.42, tokens: 0)]
        s.models = [Row(id: "Sonnet 5.5", cost: 0.42, tokens: 0)]
        s.daily = days([0, 0, 0, 0, 0, 0, 0.42])
        return Popover(snapshot: s)
    }

    private static var trouble: Popover {
        var s = base(.normal, title: "$17.80 today", pct: 0) // no 5-hour card, so the day's spend
        s.calibrated = false
        s.tapSeen = nil
        s.probeStatus = "Probe failed: Claude Code is signed out (run claude, then /login) · retry \(Fmt.when(Date().addingTimeInterval(30 * 60)))"
        var w = weekly(55, left: 2.4 * 86400, landing: 84, projection: "7-day pace: ~84% at reset",
                       budget: "Budget ~19%/day to the reset · this week's average 12%/day")
        w.accuracy = nil
        w.accuracyDetail = nil
        w.asOf = now.addingTimeInterval(-5 * 3600)
        s.weekly = w
        s.todayCost = 17.8
        s.todayTokens = 41_000_000
        s.projects = [Row(id: "Pocket Saloon", cost: 17.8, tokens: 0)]
        s.models = [Row(id: "Opus 5.5", cost: 17.8, tokens: 0)]
        s.daily = days([60, 75, 30, 0, 44, 52, 17.8])
        return Popover(snapshot: s,
                       notice: "No 5-hour window is open, and a probe would start one. It will sync after your next message.")
    }

    private static var week: Popover {
        var p = warn
        p.snapshot.weekShares = [
            Share(id: "Pocket Saloon", pct: 41, cost: 610), Share(id: "Frontier Universe", pct: 14, cost: 205),
            Share(id: "Claude Meter", pct: 9, cost: 131), Share(id: "Five Card Poker", pct: 3, cost: 44),
        ]
        p.snapshot.weekElsewhere = 6
        p.weekScope = true
        return p
    }

    private static var long: Popover {
        var p = critical
        let name = "An extraordinarily long project name that keeps going"
        p.snapshot.burning = [
            // Its name is shared with a cold row, so both are tagged: here the longest tag there is.
            Burn(id: "a", name: name, model: "Sonnet 5.5", perHour: 1240, pctPerHour: 140, tag: "started 9:41 PM"),
            Burn(id: "b", name: "Another session with a very long custom title", model: "Opus 5.5", perHour: 312, pctPerHour: 38),
            Burn(id: "c", name: "Pocket Saloon", model: "Haiku 4.5", perHour: 0.04, pctPerHour: 0.02),
            Burn(id: "f", name: "Claude Meter", model: "claude-experimental-9", perHour: 12.5, pctPerHour: 7.6),
        ]
        p.snapshot.runaways = [Runaway(id: "a", name: name, pct: 64), Runaway(id: "b", name: "Another", pct: 21)]
        p.snapshot.cooling = [
            Cooling(id: "d", name: name, coldAt: now.addingTimeInterval(59 * 60), extra: 41.8, extraPct: 25, tag: "59m"),
            Cooling(id: "e", name: "Short", coldAt: now.addingTimeInterval(60), extra: 0.01, extraPct: nil),
        ]
        p.snapshot.todayCost = 4_812
        p.snapshot.todayTokens = 1_420_000_000
        p.snapshot.projects = [Row(id: name, cost: 4_100, tokens: 0), Row(id: "Pocket Saloon", cost: 690, tokens: 0),
                               Row(id: "x", cost: 22, tokens: 0), Row(id: "Claude Meter", cost: 0.004, tokens: 0)]
        p.snapshot.daily = days([1200, 4_812, 300, 0, 0, 2_200, 4_812])
        return p
    }

    /// A plan with no separate Fable limit: the card says so over this Mac's Fable use.
    private static var nofable: Popover {
        var p = calm
        p.snapshot.fable = FableView(limit: nil, noLimit: true, fiveHourCost: 1.1, fiveHourPts: 2.8,
                                     weekCost: 6.2, weekTokens: 2_300_000, weekPts: 0.9, todayCost: 2.2)
        return p
    }

    // MARK: - History states

    private static func plans(current: Plan, _ rows: [(Plan, Int, Double, Double?, Date?, Bool)]) -> [PlanFit] {
        rows.map { PlanFit(plan: $0.0, current: $0.0 == current, capped: $0.1, peak: $0.2, weekAtReset: $0.3,
                           weekRunsOut: $0.4, weekOver: $0.5) }
    }

    private static var fits: History {
        var h = History()
        h.calibrated = true
        let peaks: [Double] = [12, 31, 8, 44, 22, 5, 58, 19, 37, 9, 26, 41]
        h.windows = peaks.enumerated().map { i, peak in
            // The last one is still open: it began two hours ago.
            let start = i == peaks.count - 1 ? now.addingTimeInterval(-2 * 3600)
                : now.addingTimeInterval(-Double(peaks.count - i) * 13 * 3600)
            return HistoryWindow(start: start, end: start.addingTimeInterval(5 * 3600), peak: peak,
                                 exact: i % 3 != 1, open: i == peaks.count - 1)
        }
        h.weekStart = now.addingTimeInterval(-3.5 * 86400)
        h.weekEnd = h.weekStart!.addingTimeInterval(7 * 86400)
        h.weekSeries = climb(from: h.weekStart!, to: 35)
        h.weekNow = 35
        h.weekAtReset = 70
        h.weekRate = 0.42
        h.exactSince = now.addingTimeInterval(-6 * 86400)
        h.plans = plans(current: .max5x, [
            (.pro, 4, 290, nil, now.addingTimeInterval(86400), false),
            (.max5x, 0, 58, 70, nil, false),
            (.max20x, 0, 15, 18, nil, false),
        ])
        return h
    }

    private static var uncalibrated: History {
        var h = History()
        h.plans = plans(current: .max5x, [
            (.pro, 0, 0, nil, nil, false), (.max5x, 0, 0, nil, nil, false), (.max20x, 0, 0, nil, nil, false),
        ])
        return h
    }
}
