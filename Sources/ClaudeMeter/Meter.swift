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
    /// Set when Anthropic reset this window's usage before its time: it counts from then.
    var restartedAt: Date?
    /// Readings keep arriving but none has measured this window for ten minutes (a probe left it
    /// out; they come every minute), so its % is the last measurement plus this Mac's spend since, which says nothing if
    /// Anthropic reset it in between. No alert is raised from it; it is raised once it is measured.
    var stale = false

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
    /// When the session last ran ("18m"), set only while another row shows the same name.
    var tag: String? = nil
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
    /// When the session last ran ("18m"), set only while another row shows the same name.
    var tag: String? = nil
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
    /// Any exact reading at all, so the empty 5-hour card doesn't read like a first install.
    var hasReading = false
    /// Set to the last exact reading's time while Claude Code is in use but no exact reading has come
    /// for an hour: the probe and the statusline have stopped working (an update, a sign-out), and
    /// every number is an estimate. With the probe's last error, if it had one.
    var readingsStoppedSince: Date?
    var probeError: String?
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
    /// What time it is. Only the replay test sets it, to step the meter through the past.
    var clock: () -> Date = Date.init
    /// Where the logs start (`LogIndex.coveredFrom`).
    var coveredFrom = Date.distantPast
    // Internal rather than private where the replay test (Replay.swift) drives the meter.
    let store = StateStore()
    private lazy var notifier = Notifier(store: store)
    /// Sorted by time. `spent[i]` is the cost of `turns[..<i]`, so any range costs two lookups.
    var turns: [Turn] = [] {
        didSet {
            var running = 0.0
            spent = [0] + turns.map { running += $0.cost; return running }
        }
    }
    private var spent: [Double] = [0]
    private var active: [String] = []
    private var names: [String: String] = [:]
    /// When this meter first had its logs to look at (its clock, so the replay's too): the readings-stopped
    /// alert doesn't count time it wasn't running.
    private var watchingSince: Date?
    var loaded = false
    private var scanning = false
    private var tapMTime: Date?
    private var probing = false
    private var timer: Timer?
    var quiet = false
    /// Cap warning, with some hysteresis so a wobbling pace doesn't flip the menu bar every tick.
    private var warningOn = false
    private var warningWindow: Date?
    /// The history log, read incrementally: readings so far, and how far the file was read.
    private var historyReadings: [ExactReading] = []
    private var historyEnd: UInt64 = 0
    /// Uptime of the last history compaction: at launch, then daily, since the app runs for weeks.
    private var compactedAt: TimeInterval = 0
    /// When the last probe finished, whatever it found.
    /// When the last probe was launched, whatever it came to. New activity has to be after this to
    /// call for another, or an answer that was turned away would be asked for again every minute.
    private var lastProbe: Date?
    /// Probes that failed in a row, for the retry wait.
    private var probeFailures = 0
    /// What takes a reading; swapped for a fake where the probe can't be run.
    var probe: () async -> Probe.Outcome = { await Probe.run() }

    private static let fiveHours: TimeInterval = 5 * 3600
    private static let week: TimeInterval = 7 * 86400
    private static let logSpan: TimeInterval = 8 * 86400
    private static let burnLookback: TimeInterval = 900
    /// An exact reading at most this often, and only after new activity.
    private static let probeEvery: TimeInterval = 60
    /// A single session using this much of the 5-hour window within 30 minutes is flagged.
    private static let runawayPct: Double = 20
    /// The cards' titles, which the alerts are also filed under.
    static let fiveHourTitle = "5-hour window"
    static let weeklyTitle = "Weekly · all models"
    /// Bump when the cost of a turn changes meaning, so calibration relearns instead of drifting.
    /// 2: the largest copy of each turn counts (0.8).
    /// Not for a price change on a model that is a sliver of the spend (Haiku 5.5 in 0.9.2 was 0.1% of
    /// the tokens, $1.44 against $3.71 over a week): relearning both caps would show for hours to fix
    /// a change smaller than their rounding.
    private static let costBasis = 2

    /// A 5-hour window opens at its first message rounded down to the 10-minute mark (every
    /// window in the history log starts on :x0:00, 0-9 minutes before its first message).
    private static func windowOpening(_ firstMessage: Date) -> Date {
        Date(timeIntervalSince1970: (firstMessage.timeIntervalSince1970 / 600).rounded(.down) * 600)
    }
    private static let blockedNotice =
        "Notifications are blocked for Claude Meter. Turn them on in the settings pane that just opened."
    private static let loadingNotice = "Still reading your Claude Code logs. Try Sync again in a moment."
    private static let noWindowNotice =
        "No 5-hour window is open, and a probe would start one. It will sync after your next message."

    func start() {
        _ = notifier // set as the notification delegate before anything is posted
        // Here rather than on the log queue: readings are appended on the main actor, and one
        // landing between compact's read and its rename would be lost.
        HistoryLog.compact()
        compactedAt = ProcessInfo.processInfo.systemUptime
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
        let uptime = ProcessInfo.processInfo.systemUptime
        if uptime - compactedAt > 86400 {
            HistoryLog.compact()
            compactedAt = uptime
        }
        scan()
        if loaded {
            readTap()
            sync(force: false)
        }
    }

    /// Called when the dropdown opens, so it never shows data up to a tick old.
    /// Open at login can change under us (System Settings > Login Items), so the menu asks first.
    func refreshLaunchAtLogin() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func refreshNow() {
        refreshLaunchAtLogin()
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
            let covered = index.coveredFrom
            Task { @MainActor in
                guard let self else { return }
                self.scanning = false
                self.coveredFrom = covered
                if let turns { self.turns = turns }
                self.active = active
                self.names = names
                if !self.loaded {
                    self.loaded = true
                    if self.notice == Self.loadingNotice { self.notice = nil }
                    // A reading saved before the logs were read has not calibrated anything yet.
                    if let r = self.store.state.lastExact { self.calibrate(from: r, fresh: Self.measured(by: r)) }
                    self.readTap()
                    self.sync(force: false)
                }
                self.recompute()
            }
        }
    }

    private func take(from index: LogIndex) {
        turns = index.turns
        coveredFrom = index.coveredFrom
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

    /// Runs the probe once a minute while a window is open, whether or not anything was logged here:
    /// use this Mac can't see (cloud sessions, claude.ai, the phone) moves it too, and a probe is a
    /// tiny Haiku turn. With no window open it waits for a message here: a probe would open one.
    /// Forced (Sync) runs regardless of timing. Either way, never when it would open a window.
    /// A failure waits before trying again: a minute, doubling to half an hour, or five minutes
    /// when only you can fix it (signed out).
    func sync(force: Bool) {
        guard !probing, !quiet else { return }
        let now = clock()
        // Before the first scan there's no telling whether a window is open.
        guard loaded else {
            if force { notice = Self.loadingNotice }
            return
        }
        guard windowOpen(now) else {
            if force { notice = Self.noWindowNotice }
            return
        }
        if !force {
            // A retry time far ahead was set under a clock that has since been put back.
            if let retry = store.state.probeRetryAt, now < retry, retry < now.addingTimeInterval(3600) { return }
            if let last = store.state.lastExact {
                // Timed from the last reading or the last probe, whichever is later: a probe whose
                // answer added nothing would otherwise run again on the next tick. A clock set back
                // since the reading counts as due (a probe from before it doesn't count at all).
                let clockWentBack = last.at > now.addingTimeInterval(60)
                let probed = lastProbe.flatMap { $0 <= now ? $0 : nil }
                let since = clockWentBack ? (probed ?? .distantPast) : max(last.at, probed ?? .distantPast)
                guard now.timeIntervalSince(since) >= Self.probeEvery else { return }
            }
        }
        // Stamped at launch, not when it answers: a turn logged while it runs is after the reading, so
        // the estimate carries it and the next probe is called for by it, rather than it falling
        // between the two.
        let launched = clock()
        lastProbe = launched
        probing = true
        recompute()
        Task {
            let outcome = await probe()
            probing = false
            switch outcome {
            case .reading(var reading):
                // At launch, unless it took so long (the Mac slept) that the answer is of a later moment.
                let answered = clock()
                reading.at = answered.timeIntervalSince(launched) > Self.slowProbe ? answered : launched
                probeFailures = 0
                store.state.probeError = nil
                store.state.probeRetryAt = nil
                if notice == Self.noWindowNotice { notice = nil }
                absorb(reading)
            case .failed(let reason):
                // A minute at first, doubling to half an hour; a failure only you can fix (signed out,
                // no CLI) waits five minutes: such a probe fails at once and spends nothing, so the
                // wait only limits how often it starts, and you are noticed back soon after you log in.
                probeFailures += 1
                let wait = Probe.needsYou(reason) ? 300 : min(1800, 60 * pow(2, Double(probeFailures - 1)))
                store.state.probeError = reason
                store.state.probeRetryAt = clock().addingTimeInterval(wait)
            }
            store.save()
            recompute()
        }
    }

    /// A probe is a request, and a request opens a 5-hour window if none is open, moving your
    /// reset. So only probe while this Mac's own activity shows a window is already open: the
    /// last reading's window hasn't reset, or a message went out after it did. With no reading
    /// to go on, only right after a message.
    func windowOpen(_ now: Date) -> Bool {
        guard let latest = turns.last?.at else { return false }
        if let resets = store.state.lastExact?.fiveHour?.resetsAt {
            // A message after the reset opened a window, but that one ends too. Not the last two minutes
            // before it: a probe launched then can reach the API after the reset and open the next one.
            return now < resets.addingTimeInterval(-Self.resetMargin) || openWindow(after: resets, now: now) != nil
        }
        return now.timeIntervalSince(latest) < 600
    }

    /// When the 5-hour window open at `now` opened, walking forward from a reset: each window
    /// opens at the first message after the last one closed. Nil when none is open.
    private func openWindow(after anchor: Date, now: Date) -> Date? {
        var anchor = anchor
        while true {
            let i = first(atOrAfter: anchor)
            guard i < turns.count, turns[i].at <= now else { return nil }
            let opened = Self.windowOpening(turns[i].at)
            let end = opened.addingTimeInterval(Self.fiveHours)
            if end > now { return opened }
            anchor = end
        }
    }

    func absorb(_ incoming: ExactReading) {
        let now = clock()
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
        var restarted: Set<String> = []
        if let last = store.state.lastExact {
            // Newer than what's held, unless the clock was set back since that was taken.
            guard reading.at > last.at || last.at > now.addingTimeInterval(60) else { return }
            // Windows saved before they carried their own time were measured with their reading.
            func dated(_ w: Window?) -> Window? { w.map { var d = $0; d.at = d.at ?? last.at; return d } }
            var isFresh = false
            let measuredNow = reading.source != "tap"
            (reading.fiveHour, isFresh) = pick(reading.fiveHour, over: dated(last.fiveHour), span: Self.fiveHours,
                                               measuredNow: measuredNow)
            if isFresh { fresh.insert("5h") }
            (reading.weekly, isFresh) = pick(reading.weekly, over: dated(last.weekly), span: Self.week,
                                             measuredNow: measuredNow)
            if isFresh { fresh.insert("week") }
            // A window Anthropic just reset early: the estimate before it couldn't have known (so it
            // isn't scored), and the window's 80% and 95% alerts can go out again.
            if let r = reading.fiveHour?.restartedAt, r != last.fiveHour?.restartedAt {
                restarted.insert("5h")
                rearmAlerts([Self.fiveHourTitle, "pace"], resets: reading.fiveHour!.resetsAt)
            }
            if let r = reading.weekly?.restartedAt, r != last.weekly?.restartedAt {
                restarted.insert("week")
                rearmAlerts([Self.weeklyTitle], resets: reading.weekly!.resetsAt)
            }
            // The tap reports no per-model buckets; keep the last ones known until they reset.
            if reading.extras.isEmpty { reading.extras = last.extras.filter { now < $0.value.resetsAt } }
        } else {
            if reading.fiveHour != nil { fresh.insert("5h") }
            if reading.weekly != nil { fresh.insert("week") }
        }
        // Nothing new in it (a statusline redrawing old numbers): not a reading.
        guard !fresh.isEmpty else { return }

        recordAccuracy(reading, fresh: fresh.subtracting(restarted))
        calibrate(from: reading, fresh: fresh)
        // The history log is a file in the real support folder, so a read-only store (the replay,
        // a test harness) never adds to it, whatever else it does.
        if !quiet, !store.readOnly { HistoryLog.append(reading) }
        store.state.lastExact = reading
        store.save()
        recompute()
    }

    /// The windows a reading measured itself, not ones it carried over from an earlier reading.
    static func measured(by r: ExactReading) -> Set<String> {
        var own: Set<String> = []
        if let w = r.fiveHour, abs((w.at ?? r.at).timeIntervalSince(r.at)) < 1 { own.insert("5h") }
        if let w = r.weekly, abs((w.at ?? r.at).timeIntervalSince(r.at)) < 1 { own.insert("week") }
        return own
    }

    /// The newer of two measurements of a window, and whether it's the new one. A window the
    /// new reading lacks carries over while it hasn't reset. `measuredNow`: the number was
    /// measured at the reading's time (a probe, a drop-in), not carried by the statusline.
    private func pick(_ new: Window?, over old: Window?, span: TimeInterval, measuredNow: Bool) -> (Window?, Bool) {
        // A window the new reading lacks is kept, reset or not: still running, or the last known
        // reset to walk on from. (The statusline drops a window the moment it resets.)
        guard var new else { return (old, false) }
        if let old {
            // A window that reset before the one already held is an old number re-sent.
            if new.resetsAt < old.resetsAt.addingTimeInterval(-900) { return (old, false) }
            if Window.same(old.resetsAt, new.resetsAt) {
                // The statusline stamps when it redraws, not when its number was measured, so
                // from it an unchanged number, or a lower one, is an old one again.
                if !measuredNow, new.pct <= old.pct + 0.5 { return (old, false) }
                // And once Anthropic has reset a window early it may redraw numbers from before,
                // higher than the window now is, which would read as a climb; the probe a minute
                // apart has the window instead.
                if !measuredNow, old.restartedAt != nil { return (old, false) }
                // Measured now, a drop of a few points is Anthropic resetting the window's usage
                // before its time; it happened after the last higher measurement. A smaller one is
                // an old number re-sent. Otherwise the window keeps any such reset it had.
                if measuredNow, new.pct < old.pct - 0.5, new.pct >= old.pct - Self.restartDrop { return (old, false) }
                if new.pct < old.pct - Self.restartDrop {
                    Self.markRestart(&new, after: old)
                } else {
                    new.restartedAt = old.restartedAt
                    new.restartedLate = old.restartedLate
                }
            } else if measuredNow, new.resetsAt.addingTimeInterval(-span) < old.resetsAt.addingTimeInterval(-60) {
                // A later window that began before the held one was due to reset (a window opens at
                // or after the last one's reset): Anthropic ended that one early.
                Self.markRestart(&new, after: old)
            }
        }
        return (new, true)
    }

    /// Notes that Anthropic reset a window early, as near as the readings can tell: right after the
    /// last time the old one was measured. If that was long ago (nothing was measuring, so the reset
    /// could be anywhere after it) it is marked late: it still counts from there, which can put a
    /// little of the old window's spend into the new one (only shrinking "Elsewhere"; on Oct 7 the
    /// reset was seen at 04:28 and had happened at 03:24, so counting from when it was seen showed the
    /// week at 0.1% of shares and the old week climbing to 96%), but it can't teach a cap.
    private static func markRestart(_ new: inout Window, after old: Window) {
        let seen = new.at ?? old.at ?? .distantPast
        guard let last = old.at else { // never measured: when it was seen is all there is
            new.restartedAt = seen
            new.restartedLate = true
            return
        }
        new.restartedAt = last
        new.restartedLate = seen.timeIntervalSince(last) > 1800 ? true : nil
    }

    /// Forgets that a window's alerts went out, so they can again: Anthropic reset its usage early.
    private func rearmAlerts(_ kinds: [String], resets: Date) {
        store.state.notified.removeAll { key in
            let parts = key.split(separator: "|")
            guard parts.count == 3, kinds.contains(String(parts[0])), let epoch = Double(parts[1]) else { return false }
            return Window.same(Date(timeIntervalSince1970: epoch), resets)
        }
    }

    /// How the meter's estimate has held up: what it would have shown for this reading's moment
    /// knowing only a reading 15 to 60 minutes older (the estimate as you see it when readings
    /// stall), against what this reading says. Readings come about once a minute while you work, so
    /// scoring against the previous one would measure almost nothing. At most one check per window
    /// per 15 minutes, so the last twenty cover hours, not minutes. Not a window at the cap (it stops
    /// climbing at 100%) nor one Anthropic reset early in between; and an estimate that had the wrong
    /// window altogether is counted apart (`accuracyUnscored`), not dropped quietly.
    private static let checkLag: ClosedRange<TimeInterval> = 900...3600
    private static let checkEvery: TimeInterval = 900
    /// How many checks are kept (the replay keeps all of its own).
    var checkLimit = 200
    /// Readings that had a check coming but whose estimate had the wrong window.
    private(set) var accuracyUnscored = 0

    private func recordAccuracy(_ reading: ExactReading, fresh: Set<String>) {
        guard loaded else { return }
        let cal = store.state.calibration
        var checks = store.state.checks ?? []
        var history: [ExactReading]?
        for (name, exactWindow, cap) in [("5h", reading.fiveHour, cal.cap5h), ("week", reading.weekly, cal.capWeek)] {
            guard fresh.contains(name), cap != nil, let exact = exactWindow, exact.pct < 99 else { continue }
            if let last = checks.last(where: { $0.window == name }),
               reading.at.timeIntervalSince(last.at) < Self.checkEvery { continue }
            let readings = history ?? exactHistory(since: reading.at.addingTimeInterval(-Self.checkLag.upperBound))
            history = readings
            guard let anchor = readings.last(where: {
                      Self.checkLag.contains(reading.at.timeIntervalSince($0.at)) && Self.measured(by: $0).contains(name)
                  }),
                  let held = name == "5h" ? anchor.fiveHour : anchor.weekly, held.pct < 99 else { continue }
            if let reset = exact.restartedAt, reset >= (held.at ?? anchor.at) { continue }
            let shown = estimate(from: anchor, at: reading.at)
            guard let est = name == "5h" ? shown.fiveHour : shown.weekly, !est.idle, let resets = est.resetsAt else { continue }
            guard abs(resets.timeIntervalSince(exact.resetsAt)) < (name == "5h" ? 900 : 3600) else {
                accuracyUnscored += 1
                continue
            }
            checks.append(Check(at: reading.at, window: name, estimated: est.pct, exact: exact.pct,
                                minutesSinceExact: reading.at.timeIntervalSince(anchor.at) / 60, anchor: held.pct))
        }
        store.state.checks = Array(checks.suffix(checkLimit))
    }

    /// What the meter would show for `at` if `anchor` were the only reading it had.
    private func estimate(from anchor: ExactReading, at: Date) -> (fiveHour: WindowView?, weekly: WindowView?) {
        let held = store.state.lastExact
        store.state.lastExact = anchor
        defer { store.state.lastExact = held }
        return (fiveHour(at), weekly(at))
    }

    private func setAccuracy(_ v: inout WindowView, window: String) {
        let recent = (store.state.checks ?? []).filter { $0.window == window }.suffix(20)
        guard !recent.isEmpty else { return }
        let errors = recent.map { $0.estimated - $0.exact }
        let typical = errors.map(abs).reduce(0, +) / Double(errors.count)
        let bias = errors.reduce(0, +) / Double(errors.count)
        var text = String(format: "Estimates made 15 to 60 minutes after a reading have been within ±%.1f pts", typical)
        text += " over \(recent.count) check\(recent.count == 1 ? "" : "s")"
        if recent.count >= 3, abs(bias) >= 1 { text += bias > 0 ? ", usually high" : ", usually low" }
        v.accuracy = String(format: "±%.1f", typical)
        v.accuracyDetail = text + "."
    }

    /// Learns each cap from a fresh measurement: logged spend in the window / fraction used.
    private func calibrate(from r: ExactReading, fresh: Set<String>) {
        guard loaded else { return }
        var c = store.state.calibration
        // At most every 15 minutes, and never the same reading twice (a relaunch replays it),
        // unless the last update is in the future: the clock has been set back since.
        if let last = c.updatedAt, last <= clock().addingTimeInterval(60), r.at.timeIntervalSince(last) < 900 { return }
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

    /// How far a window's % must fall, measured, to be Anthropic resetting it early (they fall by tens).
    static let restartDrop = 3.0
    /// How long Claude Code can be in use without an exact reading before that's a failure, not a lull.
    static let stalledAfter: TimeInterval = 3600
    /// A window the latest reading is this much newer than its last measurement is `stale`. Ten
    /// minutes: at half an hour the weekly had already climbed from 87% to 95% on spend alone.
    static let staleAfter: TimeInterval = 600
    /// A probe doesn't run this close to a reset: it could reach the API after it and open the next window.
    static let resetMargin: TimeInterval = 120
    /// Longer than this between launching a probe and its answer, the reading is dated at the answer.
    static let slowProbe: TimeInterval = 90

    /// The cap a measurement implies, when it can support one: taken within the last hour and
    /// inside its own window, with the logs reaching back over the window's start (where it began,
    /// if Anthropic reset it early), and a % high enough that whole-percent rounding doesn't
    /// dominate it. Not a window whose early reset was noticed late: the spend since is unknown. Not at the cap: a reading held at 100% while spend goes on (extra usage) would
    /// make the cap look bigger than it is.
    private func impliedCap(_ w: Window, span: TimeInterval, at: Date, minPct: Double, minSpend: Double) -> Double? {
        let now = clock()
        let start = max(w.resetsAt.addingTimeInterval(-span), w.restartedAt ?? .distantPast)
        guard w.pct >= minPct, w.pct < 99, now.timeIntervalSince(at) < 3600, at > start, at < w.resetsAt,
              start >= coveredFrom, w.restartedLate != true else { return nil }
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
        let now = clock()
        var s = Snapshot()
        s.loaded = loaded
        s.calibrated = store.state.calibration.cap5h != nil
        s.probing = probing
        if let error = store.state.probeError {
            let retry = store.state.probeRetryAt.map {
                $0 > now ? " · retry \(Fmt.when($0))" : " · retries with your next message"
            } ?? ""
            s.probeStatus = "Probe failed: \(error)\(retry)"
        }
        s.tapSeen = store.state.tapSeen
        s.hasReading = store.state.lastExact != nil
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
            s.runaways = runaways(recent)
            // A runaway keeps its ⚠ row in Burning now for its whole 30 minutes, even once it has gone
            // quiet, so the alert always has a row to point to (and isn't listed as going cold too).
            let flagged = Set(s.runaways.map(\.id))
            s.burning = burning(recent, flagged: flagged)
            s.cooling = cooling(recent, now: now).filter { !flagged.contains($0.id) }
            tagSharedNames(&s, recent, now: now)
            fillToday(&s, now: now)
            fillWeekShares(&s)
            s.capWarning = updateWarning(s.fiveHour)
            // In use for an hour since the last reading (its first message after it an hour old, and one
            // in the last 15 minutes) yet nothing exact, when readings come about once a minute while you
            // work. Not the first message after a break: its reading is a minute away. Counted from when
            // this meter started watching, too: work done while it was quit had no one to probe for it.
            watchingSince = watchingSince ?? now
            if let last = store.state.lastExact?.at, let latest = turns.last?.at, let watching = watchingSince,
               now.timeIntervalSince(latest) < 900,
               case let i = first(atOrAfter: max(last, watching).addingTimeInterval(1)), i < turns.count,
               now.timeIntervalSince(turns[i].at) > Self.stalledAfter {
                s.readingsStoppedSince = last
                s.probeError = store.state.probeError
            }
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

    func fiveHour(_ now: Date) -> WindowView? {
        let last = store.state.lastExact
        let cap = store.state.calibration.cap5h
        var v: WindowView

        if let last, let w = last.fiveHour, now < w.resetsAt {
            let measured = w.at ?? last.at
            let added = cap.map { cost(from: measured, to: now) / $0 * 100 } ?? 0
            let exact = cap != nil ? added < 0.5 : now.timeIntervalSince(measured) < 300
            v = WindowView(title: Self.fiveHourTitle, pct: w.pct + added, resetsAt: w.resetsAt,
                           exact: exact, asOf: measured)
            v.restartedAt = w.restartedAt
            v.stale = last.at.timeIntervalSince(measured) > Self.staleAfter
        } else if let cap {
            // The window has lapsed; find the one open now, walking from the last known reset.
            guard let opened = openWindow(after: last?.fiveHour?.resetsAt ?? turns.first?.at ?? now, now: now) else {
                return WindowView(title: Self.fiveHourTitle, pct: 0, exact: false, asOf: last?.at, idle: true)
            }
            v = WindowView(title: Self.fiveHourTitle, pct: cost(from: opened, to: now) / cap * 100,
                           resetsAt: opened.addingTimeInterval(Self.fiveHours), exact: false, asOf: last?.at)
        } else {
            // No cap yet to estimate with, but whether any window is open is still known.
            if let resets = last?.fiveHour?.resetsAt, now >= resets, openWindow(after: resets, now: now) == nil {
                return WindowView(title: Self.fiveHourTitle, pct: 0, exact: false, asOf: last?.at, idle: true)
            }
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
            v = WindowView(title: Self.weeklyTitle, pct: w.pct + added, resetsAt: w.resetsAt,
                           exact: exact, asOf: measured)
            v.restartedAt = w.restartedAt
            v.stale = last.at.timeIntervalSince(measured) > Self.staleAfter
        } else {
            // Weekly windows reset on a fixed schedule.
            guard let cap else { return nil }
            var resets = w.resetsAt
            while resets <= now { resets.addTimeInterval(Self.week) }
            v = WindowView(title: Self.weeklyTitle,
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
        guard v.pct < 100, let (perDay, label, averageLabel) = averagePerDay(now: now, pct: v.pct, resets: resets,
                                                                              restartedAt: v.restartedAt) else { return }
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
    private func averagePerDay(now: Date, pct: Double, resets: Date, restartedAt: Date?) -> (Double, String, String)? {
        // Old numbers re-sent (an earlier week, or a lower % for the same week that Anthropic
        // didn't reset early) say nothing new and would count as resets or climbs that never happened.
        var readings: [(at: Date, window: Window)] = []
        for r in exactHistory(since: now.addingTimeInterval(-Self.week)) {
            guard let w = r.weekly else { continue }
            if let held = readings.last?.window {
                if w.resetsAt < held.resetsAt.addingTimeInterval(-900) { continue }
                if Window.same(held.resetsAt, w.resetsAt), w.pct < held.pct - 0.5, w.restartedAt == nil { continue }
            }
            readings.append((at: w.at ?? r.at, window: w))
        }
        if let first = readings.first, now.timeIntervalSince(first.at) >= 3 * 86400 {
            let cap = store.state.calibration.capWeek
            // What a week used after its last reading, up to its reset, from the logs.
            func tail(_ r: (at: Date, window: Window)) -> Double {
                let logged = cap.map { cost(from: r.at, to: r.window.resetsAt) / $0 * 100 } ?? 0
                return min(logged, max(0, 100 - r.window.pct))
            }
            var used = 0.0
            for (a, b) in zip(readings, readings.dropFirst()) {
                if Window.same(a.window.resetsAt, b.window.resetsAt) {
                    // Lower: reset early in between, and used this much since.
                    used += b.window.pct < a.window.pct - 0.5 ? b.window.pct : max(0, b.window.pct - a.window.pct)
                } else if b.window.resetsAt > a.window.resetsAt {
                    used += tail(a) + b.window.pct // a reset between them
                }
            }
            if let last = readings.last {
                used += Window.same(last.window.resetsAt, resets)
                    ? max(0, pct - last.window.pct) // since the last reading
                    : tail(last) + pct               // a reset since: the old week's end, then this one
            }
            return (used / (now.timeIntervalSince(first.at) / 86400), "7-day", "7-day average")
        }
        // The week's own %, over the time it has counted for: from its start, or from the early reset.
        let from = max(resets.addingTimeInterval(-Self.week), restartedAt ?? .distantPast)
        let elapsed = now.timeIntervalSince(from) / 86400
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
            // Kept in time order, so the range asked for below is found rather than filtered out of
            // every reading on every call. Appended in order nearly always; a clock set back or a
            // drop-in out of order is sorted in.
            let inOrder = (new.first.map { first in historyReadings.last.map { first.at >= $0.at } ?? true } ?? true)
                && zip(new, new.dropFirst()).allSatisfy { $0.at <= $1.at }
            historyReadings += new
            if !inOrder { historyReadings.sort { $0.at < $1.at } }
            historyEnd = end
            let horizon = clock().addingTimeInterval(-Self.logSpan)
            let keep = historyIndex(historyReadings, firstAtOrAfter: horizon)
            if keep > 0 { historyReadings.removeFirst(keep) }
        }
        let low = historyIndex(historyReadings, firstAtOrAfter: since)
        let high = historyIndex(historyReadings, firstAfter: clock())
        return low < high ? Array(historyReadings[low..<high]) : []
    }

    /// Index of the first reading at or after `date` (binary search over readings in time order).
    private func historyIndex(_ readings: [ExactReading], firstAtOrAfter date: Date) -> Int {
        var low = 0, high = readings.count
        while low < high {
            let mid = (low + high) / 2
            if readings[mid].at < date { low = mid + 1 } else { high = mid }
        }
        return low
    }

    /// Index of the first reading after `date`.
    private func historyIndex(_ readings: [ExactReading], firstAfter date: Date) -> Int {
        var low = 0, high = readings.count
        while low < high {
            let mid = (low + high) / 2
            if readings[mid].at <= date { low = mid + 1 } else { high = mid }
        }
        return low
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

    /// Two sessions under one name (two threads in one folder, say) would read as one session both
    /// burning and going cold, so each such row is tagged with when its session last ran.
    private func tagSharedNames(_ s: inout Snapshot, _ recent: [String: Recent], now: Date) {
        // Only the rows the dropdown has room for (`SessionsSection`).
        let shown = s.burning.prefix(4).map(\.name) + s.cooling.prefix(3).map(\.name)
        let shared = Set(shown.filter { name in shown.filter { $0 == name }.count > 1 })
        guard !shared.isEmpty else { return }
        func tag(_ id: String, _ name: String) -> String? {
            guard shared.contains(name), let at = recent[id]?.lastTurn?.at else { return nil }
            let idle = now.timeIntervalSince(at)
            return idle < 90 ? "now" : Fmt.duration(idle)
        }
        for i in s.burning.indices { s.burning[i].tag = tag(s.burning[i].id, s.burning[i].name) }
        for i in s.cooling.indices { s.cooling[i].tag = tag(s.cooling[i].id, s.cooling[i].name) }
        // Two working at once both ran "now": those say when they started instead.
        let labels = s.burning.prefix(4).map { "\($0.name)\u{0}\($0.tag ?? "")" }
            + s.cooling.prefix(3).map { "\($0.name)\u{0}\($0.tag ?? "")" }
        func started(_ id: String, _ name: String, _ tag: String?) -> String? {
            guard let tag, labels.filter({ $0 == "\(name)\u{0}\(tag)" }).count > 1,
                  let first = turns.first(where: { $0.session == id }) else { return tag }
            return "started " + Fmt.when(first.at)
        }
        for i in s.burning.indices { s.burning[i].tag = started(s.burning[i].id, s.burning[i].name, s.burning[i].tag) }
        for i in s.cooling.indices { s.cooling[i].tag = started(s.cooling[i].id, s.cooling[i].name, s.cooling[i].tag) }
    }

    /// Runaways (`flagged`) first, so the dropdown's four rows always include them; then by spend.
    private func burning(_ recent: [String: Recent], flagged: Set<String>) -> [Burn] {
        let cap = store.state.calibration.cap5h
        return recent.compactMap { session, r in
            guard r.last15 > 0 || flagged.contains(session), let t = r.lastTurn else { return nil }
            let perHour = r.last15 / (Self.burnLookback / 3600)
            guard perHour >= 0.5 || flagged.contains(session) else { return nil }
            return Burn(id: session, name: names[session] ?? "…", model: Fmt.model(t.model),
                        perHour: perHour, pctPerHour: cap.map { perHour / $0 * 100 })
        }
        .sorted { a, b in
            let (fa, fb) = (flagged.contains(a.id), flagged.contains(b.id))
            return fa != fb ? fa : a.perHour > b.perHour
        }
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
            let rate = Pricing.rates(price, promptTokens: Int(context)) // a long prompt can cost more
            let write = rate.input * (ttl == 3600 ? 2 : 1.25)
            let extra = context * (write - rate.cacheRead) / 1_000_000 * (t.fast && price.fast ? 2 : 1)
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
        // From the week's start, or from the early reset that started its count again.
        let begin = max(resets.addingTimeInterval(-Self.week), w.restartedAt ?? .distantPast)
        for t in turns[first(atOrAfter: begin)...] {
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
        let now = clock()
        var h = History()
        h.calibrated = store.state.calibration.cap5h != nil
        let since = now.addingTimeInterval(-Self.week)
        let readings = exactHistory(since: since.addingTimeInterval(-Self.fiveHours))
        h.exactSince = readings.first?.at

        // The latest exact reading of each window, keyed by the minute it resets.
        func key(_ d: Date) -> Int { Int((d.timeIntervalSince1970 / 60).rounded()) }
        var latestExact: [Int: (pct: Double, at: Date)] = [:]
        for r in readings {
            guard let w = r.fiveHour else { continue }
            let at = w.at ?? r.at
            if let held = latestExact[key(w.resetsAt)], held.at >= at { continue }
            latestExact[key(w.resetsAt)] = (w.pct, at)
        }
        let known = latestExact.keys.map { Date(timeIntervalSince1970: Double($0) * 60) }.sorted()
        let knownStarts = known.map { $0.addingTimeInterval(-Self.fiveHours) }
        // Each known window's span: its 5 hours, except that where the next one began before this one
        // was due, Anthropic ended this one early, at the last time it was measured, and the next
        // is counted from there. (A window opens at or after the last one's reset, so overlap is this.)
        var spans: [(reset: Date, start: Date, end: Date)] = []
        for reset in known {
            var start = reset.addingTimeInterval(-Self.fiveHours)
            if var previous = spans.last, start < previous.end.addingTimeInterval(-900) {
                let seen = latestExact[key(previous.reset)]?.at ?? previous.start
                previous.end = min(previous.end, max(previous.start, seen))
                spans[spans.count - 1] = previous
                start = max(start, previous.end)
            }
            spans.append((reset, start, reset))
        }

        if let cap = store.state.calibration.cap5h {
            // How high a window got: its last exact reading plus what was logged after it, as
            // the live estimate works; the logs alone where no reading covers it.
            // `reset` is the reset its readings are filed under, which is later than `end` for a window
            // Anthropic cut short; the spend runs only to `end`, the rest being the next window's.
            func peak(_ start: Date, _ end: Date, reset: Date) -> (Double, Bool) {
                if let e = latestExact[key(reset)] {
                    return (e.pct + cost(from: e.at, to: min(end, now)) / cap * 100, true)
                }
                return (cost(from: start, to: min(end, now)) / cap * 100, false)
            }
            var drawn: [Date] = [] // the resets a window has been drawn for
            // Walk the windows forward from the start of the logs, so their edges are the real
            // ones (each opens at the first message after the last closed, rounded down to 10
            // minutes), snapped to the real window where an exact reading pins one down.
            var anchor = turns.first.map { Self.windowOpening($0.at) } ?? since
            while true {
                let i = first(atOrAfter: anchor)
                guard i < turns.count, turns[i].at <= now else { break }
                var start = max(Self.windowOpening(turns[i].at), anchor)
                var end = start.addingTimeInterval(Self.fiveHours)
                var reset = end
                if let span = spans.first(where: { $0.start <= start && start < $0.end }) {
                    // Never reach back into the window before; its spend is already counted.
                    start = max(span.start, anchor)
                    end = span.end
                    reset = span.reset
                } else if let next = knownStarts.first(where: { $0 > start && $0 < end }) {
                    end = next // a known window starts inside this one, so this one ended by then
                    reset = next
                }
                drawn.append(reset)
                if end > since {
                    let (height, exact) = peak(start, end, reset: reset)
                    h.windows.append(HistoryWindow(start: start, end: end, peak: height, exact: exact, open: end > now))
                }
                anchor = end
            }
            // A window with a reading but nothing logged here (all chat, say) still happened.
            for end in known where end > since && !drawn.contains(where: { Window.same($0, end) }) {
                // Not back over a window already drawn, one an early reset ended inside this one's span.
                var start = spans.first { $0.reset == end }?.start ?? end.addingTimeInterval(-Self.fiveHours)
                if let before = h.windows.map(\.end).filter({ $0 <= end }).max(), before > start { start = before }
                let (height, _) = peak(start, end, reset: end)
                h.windows.append(HistoryWindow(start: start, end: end, peak: height, exact: true, open: end > now))
            }
            h.windows.sort { $0.start < $1.start }
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
            // Hourly climb from the logs, scaled to end at the week's actual %. A week Anthropic reset
            // early climbs to the last % measured before the reset (from the logs alone if none was),
            // drops to 0, and climbs again from there.
            let restart = w.restartedAt.flatMap { $0 > start && $0 < now ? $0 : nil }
            let from = restart ?? start
            let logged = cost(from: from, to: now) / cap * 100
            let scale = logged > 0 ? w.pct / logged : 1
            var preScale = 1.0
            if let restart, let held = exactHistory(since: start).last(where: { $0.at < restart && $0.weekly != nil })?.weekly {
                let loggedBefore = cost(from: start, to: held.at ?? restart) / cap * 100
                if loggedBefore > 0 { preScale = held.pct / loggedBefore }
            }
            var t = start
            while t < now {
                if let restart, t >= restart, h.weekSeries.last.map({ $0.at < restart }) ?? true {
                    h.weekSeries.append(PacePoint(at: restart, pct: cost(from: start, to: restart) / cap * 100 * preScale))
                    h.weekSeries.append(PacePoint(at: restart.addingTimeInterval(1), pct: 0)) // a chart needs distinct times
                }
                let before = restart.map { t < $0 } ?? false
                h.weekSeries.append(PacePoint(at: t, pct: before ? cost(from: start, to: t) / cap * 100 * preScale
                                                               : cost(from: from, to: t) / cap * 100 * scale))
                t.addTimeInterval(3600)
            }
            if let restart, h.weekSeries.last.map({ $0.at < restart }) ?? true {
                h.weekSeries.append(PacePoint(at: restart, pct: cost(from: start, to: restart) / cap * 100 * preScale))
                h.weekSeries.append(PacePoint(at: restart.addingTimeInterval(1), pct: 0))
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
