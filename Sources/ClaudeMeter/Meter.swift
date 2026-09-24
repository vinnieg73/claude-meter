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
    /// When the last exact reading was taken.
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
    var todayCost = 0.0
    var todayTokens = 0
    var todayTurns = 0
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
    @Published private(set) var notice: String?

    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    @Published var showWeeklyInTitle = UserDefaults.standard.bool(forKey: "showWeeklyInTitle") {
        didSet { UserDefaults.standard.set(showWeeklyInTitle, forKey: "showWeeklyInTitle"); recompute() }
    }
    @Published var notificationsOn = UserDefaults.standard.object(forKey: "notifications") as? Bool ?? true {
        didSet { UserDefaults.standard.set(notificationsOn, forKey: "notifications") }
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

    private static let fiveHours: TimeInterval = 5 * 3600
    private static let week: TimeInterval = 7 * 86400
    private static let burnLookback: TimeInterval = 900
    private static let probeEvery: TimeInterval = 900

    func start() {
        let index = self.index
        queue.async { index.loadCache() }
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        timer?.tolerance = 3 // let macOS batch the wake-up with others
    }

    /// Saves the log index so the next launch starts warm.
    func shutdown() {
        let index = self.index
        queue.sync { index.saveCache(force: true) }
    }

    /// One synchronous pass for `--render`: no timer, no notifications, no network.
    func loadOnce() {
        quiet = true
        index.loadCache()
        index.refresh()
        index.saveCache()
        take(from: index)
        loaded = true
        if store.state.calibration.cap5h == nil, let r = store.state.lastExact { calibrate(from: r) }
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
        recompute()
        scan()
    }

    func testNotification() {
        notifier.test { [weak self] allowed in
            self?.notice = allowed ? nil
                : "Notifications are blocked for Claude Meter. Turn them on in the settings pane that just opened."
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
        queue.async { [weak self] in
            let changed = index.refresh()
            index.saveCache()
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
                    if self.store.state.calibration.cap5h == nil, let r = self.store.state.lastExact {
                        self.calibrate(from: r)
                    }
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
    /// Forced (Sync) runs regardless. A failure waits 30 minutes before trying again.
    func sync(force: Bool) {
        guard !probing else { return }
        let now = Date()
        if !force {
            if let retry = store.state.probeRetryAt, now < retry { return }
            if let last = store.state.lastExact {
                guard now.timeIntervalSince(last.at) >= Self.probeEvery,
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
                absorb(reading)
            case .failed(let reason):
                store.state.probeError = reason
                store.state.probeRetryAt = Date().addingTimeInterval(1800)
            }
            store.save()
            recompute()
        }
    }

    private func absorb(_ reading: ExactReading) {
        var reading = reading
        if let last = store.state.lastExact {
            guard reading.at > last.at else { return }
            // The tap reports no per-model buckets; keep the last ones known.
            if reading.extras.isEmpty { reading.extras = last.extras }
        }
        recordAccuracy(reading)
        calibrate(from: reading)
        store.state.lastExact = reading
        store.save()
        recompute()
    }

    /// Before a new reading replaces the old one, notes what the meter was estimating at
    /// that moment. Readings less than ten minutes apart say nothing about the estimate.
    private func recordAccuracy(_ reading: ExactReading) {
        guard loaded, let last = store.state.lastExact,
              reading.at.timeIntervalSince(last.at) >= 600 else { return }
        let minutes = reading.at.timeIntervalSince(last.at) / 60
        var checks = store.state.checks ?? []
        if let exact = reading.fiveHour, let est = fiveHour(reading.at), !est.idle,
           let resets = est.resetsAt, abs(resets.timeIntervalSince(exact.resetsAt)) < 900 {
            checks.append(Check(at: reading.at, window: "5h", estimated: est.pct, exact: exact.pct,
                                minutesSinceExact: minutes))
        }
        if let exact = reading.weekly, let est = weekly(reading.at),
           let resets = est.resetsAt, abs(resets.timeIntervalSince(exact.resetsAt)) < 3600 {
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

    /// Cap = logged spend in the window / fraction used. Blended so one odd reading
    /// (say, a burst of claude.ai chat the logs never see) does not swing it.
    private func calibrate(from r: ExactReading) {
        guard loaded else { return }
        var c = store.state.calibration
        if let last = c.updatedAt, r.at.timeIntervalSince(last) < 900 { return }
        var changed = false
        if let w = r.fiveHour, w.pct >= 5 {
            let spent = cost(from: w.resetsAt.addingTimeInterval(-Self.fiveHours), to: r.at)
            if spent > 0.5 { c.cap5h = blend(c.cap5h, spent / (w.pct / 100)); changed = true }
        }
        if let w = r.weekly, w.pct >= 3 {
            let spent = cost(from: w.resetsAt.addingTimeInterval(-Self.week), to: r.at)
            if spent > 2 { c.capWeek = blend(c.capWeek, spent / (w.pct / 100)); changed = true }
        }
        if changed {
            c.updatedAt = r.at
            store.state.calibration = c
            store.save()
        }
    }

    private func blend(_ old: Double?, _ new: Double) -> Double {
        old.map { $0 * 0.6 + new * 0.4 } ?? new
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
            s.burning = burning(now)
            fillToday(&s, now: now)
        }

        if let f = s.fiveHour {
            var title = (f.exact ? "" : "~") + Fmt.pct(f.pct)
            if let r = f.resetsAt { title += " · " + Fmt.duration(r.timeIntervalSince(now)) }
            if showWeeklyInTitle, let w = s.weekly {
                title += "  wk " + (w.exact ? "" : "~") + Fmt.pct(w.pct)
            }
            s.menuTitle = title
            s.menuPct = f.pct
            s.level = max(f.level, s.weekly?.level ?? .normal)
        } else if loaded {
            s.menuTitle = Fmt.dollars(s.todayCost) + " today"
        }
        snapshot = s
        if !quiet && notificationsOn { notifier.check(s, now: now) }
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
            let added = cap.map { cost(from: last.at, to: now) / $0 * 100 } ?? 0
            let exact = cap != nil ? added < 0.5 : now.timeIntervalSince(last.at) < 300
            v = WindowView(title: "5-hour window", pct: w.pct + added, resetsAt: w.resetsAt,
                           exact: exact, asOf: last.at)
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
                let opened = turns[i].at
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
            project(&v, cap: cap, now: now, windowStart: resets.addingTimeInterval(-Self.fiveHours),
                    lookback: 1800, minLookback: 600)
        }
        return v
    }

    private func weekly(_ now: Date) -> WindowView? {
        guard let last = store.state.lastExact, let w = last.weekly else { return nil }
        let cap = store.state.calibration.capWeek
        var v: WindowView

        if now < w.resetsAt {
            let added = cap.map { cost(from: last.at, to: now) / $0 * 100 } ?? 0
            let exact = cap != nil ? added < 0.5 : now.timeIntervalSince(last.at) < 300
            v = WindowView(title: "Weekly · all models", pct: w.pct + added, resetsAt: w.resetsAt,
                           exact: exact, asOf: last.at)
        } else {
            // Weekly windows reset on a fixed schedule.
            guard let cap else { return nil }
            var resets = w.resetsAt
            while resets <= now { resets.addTimeInterval(Self.week) }
            v = WindowView(title: "Weekly · all models",
                           pct: cost(from: resets.addingTimeInterval(-Self.week), to: now) / cap * 100,
                           resetsAt: resets, exact: false, asOf: last.at)
        }

        if let cap, let resets = v.resetsAt {
            project(&v, cap: cap, now: now, windowStart: resets.addingTimeInterval(-Self.week),
                    lookback: 86400, minLookback: 7200)
        }
        return v
    }

    /// Per-model weekly buckets are only known from exact readings; shown as of then.
    private func extras(_ now: Date) -> [WindowView] {
        guard let last = store.state.lastExact else { return [] }
        return last.extras
            .filter { now < $0.value.resetsAt }
            .sorted { $0.key < $1.key }
            .map { WindowView(title: $0.key, pct: $0.value.pct, resetsAt: $0.value.resetsAt,
                              exact: false, asOf: last.at) }
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
        if atReset >= 100 {
            let capAt = now.addingTimeInterval((100 - v.pct) / perHour * 3600)
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
        let inWindow = turns[first(atOrAfter: start)..<first(atOrAfter: now.addingTimeInterval(1))]
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

    private func burning(_ now: Date) -> [Burn] {
        let since = now.addingTimeInterval(-Self.burnLookback)
        var spent: [String: Double] = [:]
        var model: [String: String] = [:]
        for t in turns.reversed() {
            if t.at < since { break }
            spent[t.session, default: 0] += t.cost
            if model[t.session] == nil { model[t.session] = t.model }
        }
        let cap = store.state.calibration.cap5h
        return spent.map { session, cost in
            let perHour = cost / (Self.burnLookback / 3600)
            return Burn(id: session, name: names[session] ?? "…",
                        model: Fmt.model(model[session] ?? ""), perHour: perHour,
                        pctPerHour: cap.map { perHour / $0 * 100 })
        }
        .filter { $0.perHour >= 0.5 }
        .sorted { $0.perHour > $1.perHour }
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
            s.todayTurns += 1
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
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
