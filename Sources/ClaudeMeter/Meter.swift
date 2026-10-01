import AppKit
import ServiceManagement

enum Level: Comparable { case normal, warn, critical }

struct PacePoint {
    let at: Date
    let pct: Double
}

struct WindowView {
    var title: String
    var pct: Double
    var resetsAt: Date?
    /// True when the number is an exact reading with nothing estimated on top.
    var exact: Bool
    /// When this window was last measured exactly.
    var asOf: Date?
    var projection: String?
    var projectionWarn = false
    /// No window open: the next message starts one.
    var idle = false
    /// How far past estimates for this window have been from the exact readings that followed:
    /// "±0.7" for the card, and a sentence for its tooltip.
    var accuracy: String?
    var accuracyDetail: String?
    /// The window so far, and where the current pace takes it.
    var start: Date?
    var series: [PacePoint] = []
    var pace: [PacePoint] = []
    /// Where the current pace lands at the reset, and when it hits the cap if that comes first.
    var atReset: Double?
    var capAt: Date?
    /// Weekly only: the same at the average pace, and what's left per day to last to reset.
    var averagePerDay: Double?
    var averageAtReset: Double?
    var averageRunsOut: Date?
    var budget: String?
    var budgetWarn = false

    var level: Level { pct >= 90 ? .critical : pct >= 70 ? .warn : .normal }
}

/// A session spending right now.
struct Burn: Identifiable {
    let id: String
    let name: String
    let model: String
    let perHour: Double
    /// Points of the 5-hour window per hour, once a cap is known.
    let pctPerHour: Double?
}

/// A session idle long enough to stop burning, whose prompt cache will expire before long.
/// Its next message after that re-writes the whole context instead of reading it from cache.
struct Cooling: Identifiable {
    let id: String
    let name: String
    let coldAt: Date
    /// What the next message would cost on top of a warm one, once the cache is cold.
    let extra: Double
    let extraPct: Double?
}

/// A session eating the 5-hour window fast enough to look like a runaway loop.
struct Runaway: Identifiable {
    let id: String
    let name: String
    /// Points of the 5-hour window used in the last 30 minutes.
    let pct: Double
}

/// A project's share of the weekly limit.
struct Share: Identifiable {
    let id: String
    let pct: Double
    let cost: Double
}

struct Row: Identifiable {
    let id: String
    let cost: Double
    let tokens: Int
}

struct DayBar: Identifiable {
    var id: Date { day }
    let day: Date
    let cost: Double
}

struct Snapshot {
    var loaded = false
    var fiveHour: WindowView?
    var weekly: WindowView?
    var extras: [WindowView] = []
    var calibrated = false
    var burning: [Burn] = []
    var runaways: [Runaway] = []
    var cooling: [Cooling] = []
    var weekShares: [Share] = []
    /// Weekly % the logs can't account for: claude.ai chat, the phone, other machines.
    var weekElsewhere: Double?
    /// Set while the 5-hour pace hits the cap before the reset: when (the reset itself while
    /// the warning holds on a pace that lands just under it).
    var capWarning: Date?
    var todayCost = 0.0
    var todayTokens = 0
    var cacheHit: Double?
    var projects: [Row] = []
    var models: [Row] = []
    var daily: [DayBar] = []
    var activeCount = 0
    var probing = false
    var probeStatus: String?
    var tapSeen: Date?
    var menuTitle = "Claude"
    var menuPct: Double = 0
    var level: Level = .normal
}

/// Joins exact readings (sparse) with the local logs (continuous). Between readings,
/// a window's % moves by logged spend divided by the calibrated cap.
@MainActor
final class Meter: ObservableObject {
    @Published private(set) var snapshot = Snapshot()
    @Published private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published private(set) var loginError: String?
    /// A one-off message for the footer, e.g. when notifications are switched off in System Settings.
    @Published var notice: String?

    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    @Published var showWeeklyInTitle = UserDefaults.standard.bool(forKey: "showWeeklyInTitle") {
        didSet { UserDefaults.standard.set(showWeeklyInTitle, forKey: "showWeeklyInTitle"); recompute() }
    }
    @Published var notificationsOn = UserDefaults.standard.object(forKey: "notifications") as? Bool ?? true {
        didSet { UserDefaults.standard.set(notificationsOn, forKey: "notifications") }
    }
    @Published var plan = Plan(rawValue: UserDefaults.standard.string(forKey: "plan") ?? "") ?? .max5x {
        didSet { UserDefaults.standard.set(plan.rawValue, forKey: "plan") }
    }
    @Published var hotkeyOn = UserDefaults.standard.object(forKey: "hotkey") as? Bool ?? true {
        didSet { UserDefaults.standard.set(hotkeyOn, forKey: "hotkey") }
    }

    private let index = LogIndex()
    private let queue = DispatchQueue(label: "claude-meter.logs", qos: .utility)
    private let store = StateStore()
    private lazy var notifier = Notifier(store: store)
    /// Sorted by time. `spent[i]` is the cost of `turns[..<i]`, so any range costs two lookups.
    private var turns: [Turn] = [] {
        didSet {
            var running = 0.0
            spent = [0] + turns.map { running += $0.cost; return running }
        }
    }
    private var spent: [Double] = [0]
    private var active: [String] = []
    private var names: [String: String] = [:]
    private var loaded = false
    private var scanning = false
    private var tapMTime: Date?
    private var probing = false
    private var timer: Timer?
    private var quiet = false
    /// Cap warning, with some hysteresis so a wobbling pace doesn't flip the menu bar every tick.
    private var warningOn = false
    private var warningWindow: Date?
    /// The history log, read incrementally: readings so far, and how far the file was read.
    private var historyReadings: [ExactReading] = []
    private var historyEnd: UInt64 = 0

    private static let fiveHours: TimeInterval = 5 * 3600
    private static let week: TimeInterval = 7 * 86400
    private static let logSpan: TimeInterval = 8 * 86400
    private static let burnLookback: TimeInterval = 900
    private static let probeEvery: TimeInterval = 900
    private static let probeEveryNearCap: TimeInterval = 300
    /// A single session using this much of the 5-hour window within 30 minutes is flagged.
    private static let runawayPct: Double = 20
    /// Bump when the cost of a turn changes meaning, so calibration relearns instead of drifting.
    /// 2: the largest copy of each turn counts (0.8).
    private static let costBasis = 2

    /// A 5-hour window opens at its first message rounded down to the 10-minute mark (every
    /// window in the history log starts on :x0:00, 0-9 minutes before its first message).
    private static func windowOpening(_ firstMessage: Date) -> Date {
        Date(timeIntervalSince1970: (firstMessage.timeIntervalSince1970 / 600).rounded(.down) * 600)
    }
    private static let blockedNotice =
        "Notifications are blocked for Claude Meter. Turn them on in the settings pane that just opened."
    private static let noWindowNotice =
        "No 5-hour window is open, and a probe would start one. It will sync after your next message."

    func start() {
        _ = notifier // set as the notification delegate before anything is posted
        // Here rather than on the log queue: readings are appended on the main actor, and one
        // landing between compact's read and its rename would be lost.
        HistoryLog.compact()
        let index = self.index
        queue.async { index.loadCache() }
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        timer?.tolerance = 3 // let macOS batch the wake-up with others
    }

    /// Saves the log index so the next launch starts warm. Behind a first full scan that could
    /// take a while, so quitting (or logging out) waits two seconds at most.
    func shutdown() {
        let index = self.index
        let saved = DispatchSemaphore(value: 0)
        queue.async {
            index.saveCache(force: true)
            saved.signal()
        }
        _ = saved.wait(timeout: .now() + 2)
    }

    /// One synchronous pass for `--render`: no timer, no notifications, no network, and
    /// nothing written over the running app's files.
    func loadOnce() {
        quiet = true
        store.readOnly = true
        index.loadCache()
        index.refresh()
        take(from: index)
        loaded = true
        readTap()
        recompute()
    }

    private func tick() {
        scan()
        if loaded {
            readTap()
            sync(force: false)
        }
    }

    /// Called when the dropdown opens, so it never shows data up to a tick old.
    func refreshNow() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
        recompute()
        scan()
    }

    func testNotification() {
        notifier.test { [weak self] allowed in
            self?.notice = allowed ? nil : Self.blockedNotice
            if !allowed, let pane = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                NSWorkspace.shared.open(pane)
            }
        }
    }

    private func scan() {
        guard !scanning else { return }
        scanning = true
        let index = self.index
        let firstScan = !loaded // a warm cache can make the first refresh "unchanged"
        let readOnly = quiet
        queue.async { [weak self] in
            let changed = index.refresh()
            if !readOnly { index.saveCache() }
            let turns: [Turn]? = changed || firstScan ? index.turns : nil
            let active = index.activeSessions
            let names = index.sessionNames
            Task { @MainActor in
                guard let self else { return }
                self.scanning = false
                if let turns { self.turns = turns }
                self.active = active
                self.names = names
                if !self.loaded {
                    self.loaded = true
                    // A reading saved before the logs were read has not calibrated anything yet.
                    if let r = self.store.state.lastExact { self.calibrate(from: r, fresh: ["5h", "week"]) }
                    self.readTap()
                    self.sync(force: false)
                }
                self.recompute()
            }
        }
    }

    private func take(from index: LogIndex) {
        turns = index.turns
        active = index.activeSessions
        names = index.sessionNames
    }

    // MARK: Exact readings

    private func readTap() {
        let mtime = (try? Paths.tap.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate
        guard let mtime, mtime != tapMTime else { return }
        tapMTime = mtime
        guard let reading = TapFile.read() else { return }
        if reading.source == "tap" { store.state.tapSeen = reading.at }
        absorb(reading)
    }

    /// Runs the probe when the estimate may have drifted: the last exact reading is 15+ minutes
    /// old and something has been logged since. Idle time changes nothing, so it costs nothing.
    /// Forced (Sync) runs regardless of timing. Either way, never when it would open a window.
    /// A failure waits 30 minutes before trying again.
    func sync(force: Bool) {
        guard !probing, !quiet else { return }
        let now = Date()
        guard windowOpen(now) else {
            if force { notice = Self.noWindowNotice }
            return
        }
        if !force {
            if let retry = store.state.probeRetryAt, now < retry { return }
            if let last = store.state.lastExact {
                guard now.timeIntervalSince(last.at) >= probeInterval(now, last: last),
                      let latest = turns.last, latest.at > last.at else { return }
            }
        }
        probing = true
        recompute()
        Task {
            let outcome = await Probe.run()
            probing = false
            switch outcome {
            case .reading(let reading):
                store.state.probeError = nil
                store.state.probeRetryAt = nil
                if notice == Self.noWindowNotice { notice = nil }
                absorb(reading)
            case .failed(let reason):
                store.state.probeError = reason
                store.state.probeRetryAt = Date().addingTimeInterval(1800)
            }
            store.save()
            recompute()
        }
    }

    /// A probe is a request, and a request opens a 5-hour window if none is open, moving your
    /// reset. So only probe while this Mac's own activity shows a window is already open: the
    /// last reading's window hasn't reset, or a message went out after it did. With no reading
    /// to go on, only right after a message.
    private func windowOpen(_ now: Date) -> Bool {
        guard let latest = turns.last?.at else { return false }
        if let resets = store.state.lastExact?.fiveHour?.resetsAt {
            return now < resets || latest > resets
        }
        return now.timeIntervalSince(latest) < 600
    }

    /// Every 15 minutes normally; every 5 near the cap, where accuracy matters most; and within
    /// a minute of the first message after the window the last reading described has reset.
    private func probeInterval(_ now: Date, last: ExactReading) -> TimeInterval {
        if let resets = last.fiveHour?.resetsAt, resets < now { return 60 }
        if let f = snapshot.fiveHour, f.pct >= 75 || snapshot.capWarning != nil { return Self.probeEveryNearCap }
        return Self.probeEvery
    }

    private func absorb(_ incoming: ExactReading) {
        let now = Date()
        // A reading dated in the future (a clock ahead, a drop-in in milliseconds) would block
        // every later one.
        guard incoming.at <= now.addingTimeInterval(60) else { return }
        var reading = incoming
        func stamped(_ w: Window) -> Window {
            var n = w.normalized
            n.at = n.at ?? reading.at
            return n
        }
        reading.fiveHour = reading.fiveHour.map(stamped)
        reading.weekly = reading.weekly.map(stamped)
        reading.extras = reading.extras.mapValues(stamped)

        var fresh: Set<String> = []
        if let last = store.state.lastExact {
            guard reading.at > last.at else { return }
            // Windows saved before they carried their own time were measured with their reading.
            func dated(_ w: Window?) -> Window? { w.map { var d = $0; d.at = d.at ?? last.at; return d } }
            var isFresh = false
            (reading.fiveHour, isFresh) = pick(reading.fiveHour, over: dated(last.fiveHour), now: now)
            if isFresh { fresh.insert("5h") }
            (reading.weekly, isFresh) = pick(reading.weekly, over: dated(last.weekly), now: now)
            if isFresh { fresh.insert("week") }
            // The tap reports no per-model buckets; keep the last ones known until they reset.
            if reading.extras.isEmpty { reading.extras = last.extras.filter { now < $0.value.resetsAt } }
        } else {
            if reading.fiveHour != nil { fresh.insert("5h") }
            if reading.weekly != nil { fresh.insert("week") }
        }
        // Nothing new in it (a statusline redrawing old numbers): not a reading.
        guard !fresh.isEmpty else { return }

        recordAccuracy(reading, fresh: fresh)
        calibrate(from: reading, fresh: fresh)
        if !quiet { HistoryLog.append(reading) }
        store.state.lastExact = reading
        store.save()
        recompute()
    }

    /// The newer of two measurements of a window, and whether it's the new one. Within a
    /// window usage only climbs, so a clearly lower % for the same window is an old number
    /// re-sent. A window the new reading lacks carries over while it hasn't reset.
    private func pick(_ new: Window?, over old: Window?, now: Date) -> (Window?, Bool) {
        guard let new else {
            if let old, now < old.resetsAt { return (old, false) }
            return (nil, false)
        }
        if let old, Window.same(old.resetsAt, new.resetsAt), new.pct < old.pct - 0.5 { return (old, false) }
        return (new, true)
    }

    /// Before a new reading replaces the old one, notes what the meter was estimating at
    /// that moment. Readings a few minutes apart say little about the estimate (though near
    /// the cap they come every five, and those count), and an estimate made before there was
    /// a cap to make it with says nothing.
    private func recordAccuracy(_ reading: ExactReading, fresh: Set<String>) {
        guard loaded, let last = store.state.lastExact,
              reading.at.timeIntervalSince(last.at) >= 240 else { return }
        let minutes = reading.at.timeIntervalSince(last.at) / 60
        let cal = store.state.calibration
        var checks = store.state.checks ?? []
        if fresh.contains("5h"), cal.cap5h != nil, let exact = reading.fiveHour,
           let est = fiveHour(reading.at), !est.idle,
           let resets = est.resetsAt, Window.same(resets, exact.resetsAt) {
            checks.append(Check(at: reading.at, window: "5h", estimated: est.pct, exact: exact.pct,
                                minutesSinceExact: minutes))
        }
        if fresh.contains("week"), cal.capWeek != nil, let exact = reading.weekly,
           let est = weekly(reading.at), let resets = est.resetsAt, abs(resets.timeIntervalSince(exact.resetsAt)) < 3600 {
            checks.append(Check(at: reading.at, window: "week", estimated: est.pct, exact: exact.pct,
                                minutesSinceExact: minutes))
        }
        store.state.checks = Array(checks.suffix(200))
    }

    private func setAccuracy(_ v: inout WindowView, window: String) {
        let recent = (store.state.checks ?? []).filter { $0.window == window }.suffix(20)
        guard !recent.isEmpty else { return }
        let errors = recent.map { $0.estimated - $0.exact }
        let typical = errors.map(abs).reduce(0, +) / Double(errors.count)
        let bias = errors.reduce(0, +) / Double(errors.count)
        var text = String(format: "Estimates have been within ±%.1f pts", typical)
        text += " over \(recent.count) check\(recent.count == 1 ? "" : "s")"
        if recent.count >= 3, abs(bias) >= 1 { text += bias > 0 ? ", usually high" : ", usually low" }
        v.accuracy = String(format: "±%.1f", typical)
        v.accuracyDetail = text + "."
    }

    /// Learns each cap from a fresh measurement: logged spend in the window / fraction used.
    private func calibrate(from r: ExactReading, fresh: Set<String>) {
        guard loaded else { return }
        var c = store.state.calibration
        // At most every 15 minutes, and never the same reading twice (a relaunch replays it).
        if let last = c.updatedAt, r.at.timeIntervalSince(last) < 900 { return }
        var changed = false
        if fresh.contains("5h"), let w = r.fiveHour,
           let cap = impliedCap(w, span: Self.fiveHours, at: w.at ?? r.at, minPct: 10, minSpend: 0.5) {
            c.cap5h = blend(c.basis5h == Self.costBasis ? c.cap5h : nil, cap, pct: w.pct)
            c.basis5h = Self.costBasis
            changed = true
        }
        if fresh.contains("week"), let w = r.weekly,
           let cap = impliedCap(w, span: Self.week, at: w.at ?? r.at, minPct: 5, minSpend: 2) {
            c.capWeek = blend(c.basisWeek == Self.costBasis ? c.capWeek : nil, cap, pct: w.pct)
            c.basisWeek = Self.costBasis
            changed = true
        }
        if changed {
            c.updatedAt = r.at
            store.state.calibration = c
            store.save()
        }
    }

    /// The cap a measurement implies, when it can support one: taken within the last hour and
    /// inside its own window, with the logs reaching back over the window's start, and a % high
    /// enough that whole-percent rounding doesn't dominate it. Not at the cap: a reading held at
    /// 100% while spend goes on (extra usage) would make the cap look bigger than it is.
    private func impliedCap(_ w: Window, span: TimeInterval, at: Date, minPct: Double, minSpend: Double) -> Double? {
        let now = Date()
        let start = w.resetsAt.addingTimeInterval(-span)
        guard w.pct >= minPct, w.pct < 99, now.timeIntervalSince(at) < 3600, at > start, at < w.resetsAt,
              start > now.addingTimeInterval(-Self.logSpan + 3600) else { return nil }
        let spent = cost(from: start, to: at)
        return spent > minSpend ? spent / (w.pct / 100) : nil
    }

    /// Moves toward the new value, more the higher the % (rounding matters less there), and at
    /// most 1.5x either way in one step: usage the logs can't see (chat, the phone) drags one
    /// window's ratio down, and one such window shouldn't carry into the next.
    private func blend(_ old: Double?, _ new: Double, pct: Double) -> Double {
        guard let old else { return new }
        let weight = 0.4 * min(1, pct / 25)
        let target = min(max(new, old / 1.5), old * 1.5)
        return old * (1 - weight) + target * weight
    }

    // MARK: Snapshot

    func recompute() {
        let now = Date()
        var s = Snapshot()
        s.loaded = loaded
        s.calibrated = store.state.calibration.cap5h != nil
        s.probing = probing
        if let error = store.state.probeError {
            let retry = store.state.probeRetryAt.map { " · retry \(Fmt.when($0))" } ?? ""
            s.probeStatus = "Probe failed: \(error)\(retry)"
        }
        s.tapSeen = store.state.tapSeen
        s.activeCount = active.count
        if loaded {
            s.fiveHour = fiveHour(now)
            if var f = s.fiveHour {
                if !f.exact { setAccuracy(&f, window: "5h") }
                series(&f, now: now)
                s.fiveHour = f
            }
            s.weekly = weekly(now)
            if var w = s.weekly, !w.exact {
                setAccuracy(&w, window: "week")
                s.weekly = w
            }
            s.extras = extras(now)
            let recent = recentBySession(now)
            s.burning = burning(recent)
            s.runaways = runaways(recent)
            s.cooling = cooling(recent, now: now)
            fillToday(&s, now: now)
            fillWeekShares(&s)
            s.capWarning = updateWarning(s.fiveHour)
        }

        if let f = s.fiveHour {
            var title = (f.exact ? "" : "~") + Fmt.pct(f.pct)
            if let capAt = s.capWarning {
                title += " · cap " + Fmt.when(capAt)
            } else if let r = f.resetsAt {
                title += " · " + Fmt.duration(r.timeIntervalSince(now))
            }
            var level = max(f.level, s.capWarning != nil ? .warn : .normal)
            if showWeeklyInTitle, let w = s.weekly {
                title += "  wk " + (w.exact ? "" : "~") + Fmt.pct(w.pct)
                level = max(level, w.level) // colour only by what the title shows
            }
            s.menuTitle = title
            s.menuPct = f.pct
            s.level = level
        } else if loaded {
            s.menuTitle = Fmt.dollars(s.todayCost) + " today"
        }
        snapshot = s
        guard !quiet else { return }
        notifier.check(s, now: now, post: notificationsOn)
        // Turned on in System Settings since the test said blocked.
        if notice == Self.blockedNotice, notifier.authorized { notice = nil }
    }

    private func cost(from: Date, to: Date) -> Double {
        let a = first(atOrAfter: from), b = first(atOrAfter: to)
        return b > a ? spent[b] - spent[a] : 0
    }

    /// Index of the first turn at or after `date` (binary search over the sorted turns).
    private func first(atOrAfter date: Date) -> Int {
        var low = 0, high = turns.count
        while low < high {
            let mid = (low + high) / 2
            if turns[mid].at < date { low = mid + 1 } else { high = mid }
        }
        return low
    }

    private func fiveHour(_ now: Date) -> WindowView? {
        let last = store.state.lastExact
        let cap = store.state.calibration.cap5h
        var v: WindowView

        if let last, let w = last.fiveHour, now < w.resetsAt {
            let measured = w.at ?? last.at
            let added = cap.map { cost(from: measured, to: now) / $0 * 100 } ?? 0
            let exact = cap != nil ? added < 0.5 : now.timeIntervalSince(measured) < 300
            v = WindowView(title: "5-hour window", pct: w.pct + added, resetsAt: w.resetsAt,
                           exact: exact, asOf: measured)
        } else if let cap {
            // The window has lapsed. The next opens with the first message after it closed,
            // so walk forward window by window from the last known reset.
            var anchor = last?.fiveHour?.resetsAt ?? turns.first?.at ?? now
            while true {
                let i = first(atOrAfter: anchor)
                guard i < turns.count, turns[i].at <= now else {
                    return WindowView(title: "5-hour window", pct: 0, exact: false,
                                      asOf: last?.at, idle: true)
                }
                let opened = Self.windowOpening(turns[i].at)
                let end = opened.addingTimeInterval(Self.fiveHours)
                if end > now {
                    v = WindowView(title: "5-hour window", pct: cost(from: opened, to: now) / cap * 100,
                                   resetsAt: end, exact: false, asOf: last?.at)
                    break
                }
                anchor = end
            }
        } else {
            return nil
        }

        if let cap, let resets = v.resetsAt {
            // 20+ minutes of pace before projecting: a window's first minutes are mostly cache
            // writes and would project a cap that isn't coming.
            project(&v, cap: cap, now: now, windowStart: resets.addingTimeInterval(-Self.fiveHours),
                    lookback: 2700, minLookback: 1200)
        }
        return v
    }

    private func weekly(_ now: Date) -> WindowView? {
        guard let last = store.state.lastExact, let w = last.weekly else { return nil }
        let cap = store.state.calibration.capWeek
        let measured = w.at ?? last.at
        var v: WindowView

        if now < w.resetsAt {
            let added = cap.map { cost(from: measured, to: now) / $0 * 100 } ?? 0
            let exact = cap != nil ? added < 0.5 : now.timeIntervalSince(measured) < 300
            v = WindowView(title: "Weekly · all models", pct: w.pct + added, resetsAt: w.resetsAt,
                           exact: exact, asOf: measured)
        } else {
            // Weekly windows reset on a fixed schedule.
            guard let cap else { return nil }
            var resets = w.resetsAt
            while resets <= now { resets.addTimeInterval(Self.week) }
            v = WindowView(title: "Weekly · all models",
                           pct: cost(from: resets.addingTimeInterval(-Self.week), to: now) / cap * 100,
                           resetsAt: resets, exact: false, asOf: measured)
        }

        if let cap, let resets = v.resetsAt {
            project(&v, cap: cap, now: now, windowStart: resets.addingTimeInterval(-Self.week),
                    lookback: 86400, minLookback: 7200)
            forecast(&v, cap: cap, now: now, resets: resets)
        }
        return v
    }

    /// The last 24 hours overstate a workday and understate a weekend, so the weekly card leads
    /// with an average and gives today's pace second. The budget is what's left per day to last
    /// until the reset, set against that average.
    private func forecast(_ v: inout WindowView, cap: Double, now: Date, resets: Date) {
        guard v.pct < 100, let (perDay, label, averageLabel) = averagePerDay(now: now, pct: v.pct, resets: resets) else { return }
        let daysLeft = resets.timeIntervalSince(now) / 86400
        let atReset = v.pct + perDay * daysLeft
        v.averagePerDay = perDay
        v.averageAtReset = atReset
        if atReset >= 100, perDay > 0 {
            v.averageRunsOut = now.addingTimeInterval((100 - v.pct) / perDay * 86400)
        }

        let average = v.averageRunsOut.map { "\(label) pace: out \(Fmt.when($0))" }
            ?? "\(label) pace: ~\(Fmt.pct(atReset)) at reset"
        let today = v.capAt.map { "today's: out \(Fmt.when($0))" }
            ?? v.atReset.map { "today's: ~\(Fmt.pct($0))" }
        v.projection = [average, today].compactMap { $0 }.joined(separator: " · ")
        v.projectionWarn = v.averageRunsOut != nil

        let budget = (100 - v.pct) / max(daysLeft, 1.0 / 24)
        v.budget = "Budget ~\(Fmt.rate(budget))%/day to the reset · \(averageLabel) \(Fmt.rate(perDay))%/day"
        v.budgetWarn = perDay > budget
    }

    /// Weekly points used per day, from exact readings only. The logs price each model
    /// differently, and a model change inside the span (Opus 5 to 5.5 on Sep 22) makes a
    /// log-based average unreliable. Uses the history log's increments over the last 7 days
    /// once it covers 3+ days; before that, this week's own average once it is a day old.
    private func averagePerDay(now: Date, pct: Double, resets: Date) -> (Double, String, String)? {
        let readings = exactHistory(since: now.addingTimeInterval(-Self.week))
            .compactMap { r in r.weekly.map { (at: $0.at ?? r.at, window: $0) } }
        if let first = readings.first, now.timeIntervalSince(first.at) >= 3 * 86400 {
            let cap = store.state.calibration.capWeek
            // What a week used after its last reading, up to its reset, from the logs.
            func tail(_ r: (at: Date, window: Window)) -> Double {
                let logged = cap.map { cost(from: r.at, to: r.window.resetsAt) / $0 * 100 } ?? 0
                return min(logged, max(0, 100 - r.window.pct))
            }
            var used = 0.0
            for (a, b) in zip(readings, readings.dropFirst()) {
                used += Window.same(a.window.resetsAt, b.window.resetsAt)
                    ? max(0, b.window.pct - a.window.pct)
                    : tail(a) + b.window.pct // a reset between them
            }
            if let last = readings.last {
                used += Window.same(last.window.resetsAt, resets)
                    ? max(0, pct - last.window.pct) // since the last reading
                    : tail(last) + pct               // a reset since: the old week's end, then this one
            }
            return (used / (now.timeIntervalSince(first.at) / 86400), "7-day", "7-day average")
        }
        let elapsed = now.timeIntervalSince(resets.addingTimeInterval(-Self.week)) / 86400
        return elapsed >= 1 ? (pct / elapsed, "Week's", "this week's average") : nil
    }

    /// The history log, read only as far as it has grown since last time.
    private func exactHistory(since: Date) -> [ExactReading] {
        let size = ((try? FileManager.default.attributesOfItem(atPath: Paths.history.path))?[.size] as? NSNumber)?
            .uint64Value ?? 0
        if size < historyEnd { // compacted or replaced: start over
            historyReadings = []
            historyEnd = 0
        }
        if size > historyEnd {
            let (new, end) = HistoryLog.load(from: historyEnd)
            historyReadings += new
            historyEnd = end
            let horizon = Date().addingTimeInterval(-Self.logSpan)
            historyReadings.removeAll { $0.at < horizon }
        }
        return historyReadings.filter { $0.at >= since }
    }

    /// Per-model weekly buckets are only known from exact readings; shown as of then.
    private func extras(_ now: Date) -> [WindowView] {
        guard let last = store.state.lastExact else { return [] }
        return last.extras
            .filter { now < $0.value.resetsAt }
            .sorted { $0.key < $1.key }
            .map { WindowView(title: $0.key, pct: $0.value.pct, resetsAt: $0.value.resetsAt,
                              exact: false, asOf: $0.value.at ?? last.at) }
    }

    /// Extends recent pace to the reset: either where it lands, or when it hits the cap.
    private func project(_ v: inout WindowView, cap: Double, now: Date, windowStart: Date,
                         lookback: TimeInterval, minLookback: TimeInterval) {
        guard let resets = v.resetsAt else { return }
        if v.pct >= 100 {
            v.projection = "At the cap until \(Fmt.when(resets))"
            v.projectionWarn = true
            return
        }
        let span = min(lookback, now.timeIntervalSince(windowStart))
        guard span >= minLookback else {
            v.projection = "Measuring pace…"
            return
        }
        let perHour = cost(from: now.addingTimeInterval(-span), to: now) / cap * 100 / (span / 3600)
        let atReset = v.pct + perHour * resets.timeIntervalSince(now) / 3600
        v.atReset = atReset
        if atReset >= 100 {
            let capAt = now.addingTimeInterval((100 - v.pct) / perHour * 3600)
            v.capAt = capAt
            v.projection = "At this pace: capped at \(Fmt.when(capAt))"
            v.projectionWarn = true
            v.pace = [PacePoint(at: now, pct: v.pct), PacePoint(at: capAt, pct: 100)]
        } else {
            v.projection = "At this pace: ~\(Fmt.pct(atReset)) by reset"
            v.pace = [PacePoint(at: now, pct: v.pct), PacePoint(at: resets, pct: atReset)]
        }
    }

    /// The window's climb so far. The logs give its shape; the displayed % (which includes
    /// usage the logs never see) gives its height.
    private func series(_ v: inout WindowView, now: Date) {
        guard let resets = v.resetsAt, !v.idle else { return }
        let start = resets.addingTimeInterval(-Self.fiveHours)
        // A clock set back can put the window's start after now; there's nothing to draw then.
        guard start <= now else { return }
        let lower = first(atOrAfter: start)
        let upper = max(lower, first(atOrAfter: now.addingTimeInterval(1)))
        let inWindow = turns[lower..<upper]
        let total = inWindow.reduce(0) { $0 + $1.cost }
        var points = [PacePoint(at: start, pct: 0)]
        if total > 0 {
            // One point per 2.5 minutes is plenty for a 5-hour chart.
            var spent = 0.0
            var lastBucket = -1.0
            for t in inWindow {
                spent += t.cost
                let point = PacePoint(at: t.at, pct: spent / total * v.pct)
                let bucket = (t.at.timeIntervalSince(start) / 150).rounded(.down)
                if bucket == lastBucket { points[points.count - 1] = point } else { points.append(point) }
                lastBucket = bucket
            }
        }
        points.append(PacePoint(at: now, pct: v.pct))
        v.start = start
        v.series = points
    }

    /// One session's last hour: what burning, runaways and cooling each need.
    private struct Recent {
        var last15 = 0.0
        var last30 = 0.0
        var lastTurn: Turn?
        var hourCache = false
    }

    private func recentBySession(_ now: Date) -> [String: Recent] {
        var recent: [String: Recent] = [:]
        for t in turns.reversed() {
            let age = now.timeIntervalSince(t.at)
            if age > 3600 { break }
            var r = recent[t.session] ?? Recent()
            if r.lastTurn == nil { r.lastTurn = t }
            if age <= Self.burnLookback { r.last15 += t.cost }
            if age <= 1800 { r.last30 += t.cost }
            if t.write1h > 0 { r.hourCache = true }
            recent[t.session] = r
        }
        return recent
    }

    private func burning(_ recent: [String: Recent]) -> [Burn] {
        let cap = store.state.calibration.cap5h
        return recent.compactMap { session, r in
            guard r.last15 > 0, let t = r.lastTurn else { return nil }
            let perHour = r.last15 / (Self.burnLookback / 3600)
            return Burn(id: session, name: names[session] ?? "…", model: Fmt.model(t.model),
                        perHour: perHour, pctPerHour: cap.map { perHour / $0 * 100 })
        }
        .filter { $0.perHour >= 0.5 }
        .sorted { $0.perHour > $1.perHour }
    }

    /// On once the pace caps the window at least 10 minutes before it resets; off once the pace
    /// lands under 95% at the reset. In between it holds, so a wobbling pace doesn't flicker,
    /// and while it holds with no cap time the reset itself is when the cap comes.
    private func updateWarning(_ f: WindowView?) -> Date? {
        guard let f, !f.idle, f.pct < 100, let resets = f.resetsAt else {
            warningOn = false
            return nil
        }
        if !Window.same(warningWindow, resets) { warningOn = false }
        warningWindow = resets
        if let capAt = f.capAt {
            if capAt <= resets.addingTimeInterval(-600) { warningOn = true }
            return warningOn ? capAt : nil
        }
        if let atReset = f.atReset, atReset < 95 { warningOn = false }
        return warningOn ? resets : nil
    }

    private func runaways(_ recent: [String: Recent]) -> [Runaway] {
        guard let cap = store.state.calibration.cap5h else { return [] }
        return recent.compactMap { session, r in
            let pct = r.last30 / cap * 100
            return pct >= Self.runawayPct ? Runaway(id: session, name: names[session] ?? "…", pct: pct) : nil
        }
        .sorted { $0.pct > $1.pct }
    }

    private func cooling(_ recent: [String: Recent], now: Date) -> [Cooling] {
        let cap = store.state.calibration.cap5h
        return recent.compactMap { session, r -> Cooling? in
            guard let t = r.lastTurn else { return nil }
            let ttl: TimeInterval = r.hourCache ? 3600 : 300
            let idle = now.timeIntervalSince(t.at)
            guard idle >= Self.burnLookback, idle < ttl, let price = Pricing.price(for: t.model) else { return nil }
            // Cold, the whole prompt is written to cache again instead of read from it.
            let context = Double(t.input + t.cacheRead + t.cacheWrite)
            let write = price.input * (ttl == 3600 ? 2 : 1.25)
            let extra = context * (write - price.cacheRead) / 1_000_000 * (t.fast ? 2 : 1)
            guard extra >= 0.5 else { return nil }
            return Cooling(id: session, name: names[session] ?? t.project,
                           coldAt: t.at.addingTimeInterval(ttl), extra: extra,
                           extraPct: cap.map { extra / $0 * 100 })
        }
        .sorted { $0.coldAt < $1.coldAt }
    }

    private func fillWeekShares(_ s: inout Snapshot) {
        guard let w = s.weekly, let resets = w.resetsAt, let cap = store.state.calibration.capWeek else { return }
        var byProject: [String: Double] = [:]
        for t in turns[first(atOrAfter: resets.addingTimeInterval(-Self.week))...] {
            byProject[t.project, default: 0] += t.cost
        }
        s.weekShares = byProject.map { Share(id: $0.key, pct: $0.value / cap * 100, cost: $0.value) }
            .sorted { $0.pct > $1.pct }
        let elsewhere = w.pct - s.weekShares.reduce(0) { $0 + $1.pct }
        s.weekElsewhere = elsewhere >= 2 ? elsewhere : nil
    }

    // MARK: History

    /// The last seven days of 5-hour windows, this week's climb, and how each plan would have
    /// fared. Exact readings where the history log has them, estimates from the logs otherwise.
    func history() -> History {
        let now = Date()
        var h = History()
        h.calibrated = store.state.calibration.cap5h != nil
        let since = now.addingTimeInterval(-Self.week)
        let readings = exactHistory(since: since.addingTimeInterval(-Self.fiveHours))
        h.exactSince = readings.first?.at

        // Highest exact reading per window, keyed by the minute it resets.
        var exactPeak: [Int: Double] = [:]
        for r in readings {
            guard let w = r.fiveHour else { continue }
            let key = Int((w.resetsAt.timeIntervalSince1970 / 60).rounded())
            exactPeak[key] = max(exactPeak[key] ?? 0, w.pct)
        }
        let known = exactPeak.keys.map { Date(timeIntervalSince1970: Double($0) * 60) }.sorted()
        let knownStarts = known.map { $0.addingTimeInterval(-Self.fiveHours) }

        if let cap = store.state.calibration.cap5h {
            // Walk the windows forward: each opens with the first message after the last closed,
            // snapped to the real window where an exact reading pins one down. Starting a window
            // early catches one already running at the 7-day mark.
            var anchor = since.addingTimeInterval(-Self.fiveHours)
            while true {
                let i = first(atOrAfter: anchor)
                guard i < turns.count, turns[i].at <= now else { break }
                var start = max(Self.windowOpening(turns[i].at), anchor)
                var end = start.addingTimeInterval(Self.fiveHours)
                if let pinned = known.first(where: { $0.addingTimeInterval(-Self.fiveHours) <= start && start < $0 }) {
                    // Never reach back into the window before; its spend is already counted.
                    start = max(pinned.addingTimeInterval(-Self.fiveHours), anchor)
                    end = pinned
                } else if let next = knownStarts.first(where: { $0 > start && $0 < end }) {
                    end = next // a known window starts inside this one, so this one ended by then
                }
                let estimate = cost(from: start, to: min(end, now)) / cap * 100
                let exact = exactPeak[Int((end.timeIntervalSince1970 / 60).rounded())]
                if end > since {
                    h.windows.append(HistoryWindow(start: start, end: end, peak: max(exact ?? 0, estimate),
                                                   exact: exact != nil, open: end > now))
                }
                anchor = end
            }
        }

        if let w = weekly(now), let resets = w.resetsAt, let cap = store.state.calibration.capWeek {
            let start = resets.addingTimeInterval(-Self.week)
            h.weekStart = start
            h.weekEnd = resets
            h.weekNow = w.pct
            // Plan decisions ride on the week, so use the average, not one day's pace.
            h.weekAtReset = w.averageAtReset ?? w.atReset
            let hoursLeft = resets.timeIntervalSince(now) / 3600
            if let perDay = w.averagePerDay {
                h.weekRate = perDay / 24
            } else if let atReset = w.atReset, hoursLeft > 0 {
                h.weekRate = (atReset - w.pct) / hoursLeft
            }
            // Hourly climb from the logs, scaled to end at the week's actual %.
            let logged = cost(from: start, to: now) / cap * 100
            let scale = logged > 0 ? w.pct / logged : 1
            var t = start
            while t < now {
                h.weekSeries.append(PacePoint(at: t, pct: cost(from: start, to: t) / cap * 100 * scale))
                t.addTimeInterval(3600)
            }
            h.weekSeries.append(PacePoint(at: now, pct: w.pct))
        }

        let peak = h.windows.map(\.peak).max() ?? 0
        let week = h.weekAtReset ?? h.weekNow
        h.plans = Plan.allCases.map { p in
            let factor = plan.multiplier / p.multiplier
            var runsOut: Date?
            let over = (h.weekNow ?? 0) * factor >= 100
            if !over, let used = h.weekNow, let rate = h.weekRate, rate > 0, let end = h.weekEnd {
                let at = now.addingTimeInterval((100 - used * factor) / (rate * factor) * 3600)
                if at < end { runsOut = at }
            }
            return PlanFit(plan: p, current: p == plan,
                           capped: h.windows.filter { $0.peak * factor >= 100 }.count,
                           peak: peak * factor, weekAtReset: week.map { $0 * factor },
                           weekRunsOut: runsOut, weekOver: over)
        }
        return h
    }

    private func fillToday(_ s: inout Snapshot, now: Date) {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: now)
        var projects: [String: (Double, Int)] = [:]
        var models: [String: (Double, Int)] = [:]
        var uncached = 0, read = 0, written = 0

        var names: [String: String] = [:]
        for t in turns[first(atOrAfter: dayStart)...] {
            s.todayCost += t.cost
            s.todayTokens += t.tokens
            projects[t.project, default: (0, 0)].0 += t.cost
            projects[t.project, default: (0, 0)].1 += t.tokens
            let name = names[t.model] ?? {
                let n = Fmt.model(t.model)
                names[t.model] = n
                return n
            }()
            models[name, default: (0, 0)].0 += t.cost
            models[name, default: (0, 0)].1 += t.tokens
            uncached += t.input
            read += t.cacheRead
            written += t.cacheWrite
        }
        let prompt = uncached + read + written
        s.cacheHit = prompt > 0 ? Double(read) / Double(prompt) : nil
        s.projects = projects.map { Row(id: $0.key, cost: $0.value.0, tokens: $0.value.1) }
            .sorted { $0.cost > $1.cost }
        s.models = models.map { Row(id: $0.key, cost: $0.value.0, tokens: $0.value.1) }
            .sorted { $0.cost > $1.cost }
        s.daily = (0..<7).reversed().compactMap { back in
            guard let day = cal.date(byAdding: .day, value: -back, to: dayStart),
                  let next = cal.date(byAdding: .day, value: 1, to: day) else { return nil }
            return DayBar(day: day, cost: cost(from: day, to: next))
        }
    }

    // MARK: Settings

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
        }
        if on, SMAppService.mainApp.status == .requiresApproval {
            loginError = "Approve Claude Meter in System Settings → General → Login Items."
            SMAppService.openSystemSettingsLoginItems()
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
