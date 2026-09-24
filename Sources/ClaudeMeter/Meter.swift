import Foundation
import ServiceManagement

enum Level { case normal, warn, critical }

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

    var level: Level { pct >= 90 ? .critical : pct >= 70 ? .warn : .normal }
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
    var todayCost = 0.0
    var todayTokens = 0
    var todayTurns = 0
    var cacheHit: Double?
    var projects: [Row] = []
    var models: [Row] = []
    var daily: [DayBar] = []
    var active: [String] = []
    var apiStatus: String?
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

    private let index = LogIndex()
    private let queue = DispatchQueue(label: "claude-meter.logs", qos: .utility)
    private let store = StateStore()
    private lazy var notifier = Notifier(store: store)
    private var turns: [Turn] = []
    private var active: [String] = []
    private var loaded = false
    private var scanning = false
    private var tapMTime: Date?
    private var apiInFlight = false
    private var timer: Timer?
    private var quiet = false

    private static let fiveHours: TimeInterval = 5 * 3600
    private static let week: TimeInterval = 7 * 86400

    func start() {
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    /// One synchronous pass for `--render`: no timer, no notifications, no network.
    func loadOnce() {
        quiet = true
        index.refresh()
        turns = index.turns
        active = index.activeProjects
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

    private func scan() {
        guard !scanning else { return }
        scanning = true
        let index = self.index
        queue.async { [weak self] in
            index.refresh()
            let turns = index.turns
            let active = index.activeProjects
            Task { @MainActor in
                guard let self else { return }
                self.scanning = false
                self.turns = turns
                self.active = active
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

    /// Asks the usage endpoint when the last exact reading is over an hour old,
    /// or when forced. Always honours the endpoint's retry-after.
    func sync(force: Bool) {
        guard !apiInFlight else { return }
        let now = Date()
        if let next = store.state.apiNextAllowed, now < next { return }
        if !force, let last = store.state.lastExact, now.timeIntervalSince(last.at) < 3600 { return }
        apiInFlight = true
        Task {
            let outcome = await UsageAPI.fetch()
            apiInFlight = false
            switch outcome {
            case .reading(let reading):
                store.state.apiNextAllowed = Date().addingTimeInterval(3600)
                store.state.apiStatus = "API synced \(Fmt.when(Date()))"
                absorb(reading)
            case .retryAfter(let seconds):
                let until = Date().addingTimeInterval(max(seconds, 600))
                store.state.apiNextAllowed = until
                store.state.apiStatus = "API rate-limited until \(Fmt.when(until))"
            case .failed(let reason):
                store.state.apiNextAllowed = Date().addingTimeInterval(3600)
                store.state.apiStatus = "API: \(reason)"
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
        calibrate(from: reading)
        store.state.lastExact = reading
        store.save()
        recompute()
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
        s.apiStatus = store.state.apiStatus
        s.tapSeen = store.state.tapSeen
        s.active = active
        if loaded {
            s.fiveHour = fiveHour(now)
            s.weekly = weekly(now)
            s.extras = extras(now)
            fillToday(&s, now: now)
        }

        if let f = s.fiveHour {
            var title = (f.exact ? "" : "~") + Fmt.pct(f.pct)
            if let r = f.resetsAt { title += " · " + Fmt.duration(r.timeIntervalSince(now)) }
            s.menuTitle = title
            s.menuPct = f.pct
            s.level = max(f.level, s.weekly?.level ?? .normal)
        } else if loaded {
            s.menuTitle = Fmt.dollars(s.todayCost) + " today"
        }
        snapshot = s
        if !quiet { notifier.check(s, now: now) }
    }

    private func cost(from: Date, to: Date) -> Double {
        var total = 0.0
        for t in turns where t.at >= from && t.at < to { total += t.cost }
        return total
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
                guard let first = turns.first(where: { $0.at >= anchor }) else {
                    return WindowView(title: "5-hour window", pct: 0, exact: false,
                                      asOf: last?.at, idle: true)
                }
                let end = first.at.addingTimeInterval(Self.fiveHours)
                if end > now {
                    v = WindowView(title: "5-hour window", pct: cost(from: first.at, to: now) / cap * 100,
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
        } else {
            v.projection = "At this pace: ~\(Fmt.pct(atReset)) by reset"
        }
    }

    private func fillToday(_ s: inout Snapshot, now: Date) {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: now)
        var projects: [String: (Double, Int)] = [:]
        var models: [String: (Double, Int)] = [:]
        var uncached = 0, read = 0, written = 0

        for t in turns where t.at >= dayStart {
            s.todayCost += t.cost
            s.todayTokens += t.tokens
            s.todayTurns += 1
            projects[t.project, default: (0, 0)].0 += t.cost
            projects[t.project, default: (0, 0)].1 += t.tokens
            let name = Fmt.model(t.model)
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

extension Level: Comparable {}
