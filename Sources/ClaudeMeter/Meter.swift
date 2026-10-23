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
    /// So is a window that lapsed since the last reading: the one open now is this Mac's spend alone.
    var stale = false

    /// From the whole percent shown, so "70%" is never drawn in the colour of 69.
    var level: Level {
        let shown = pct.rounded()
        return shown >= 90 ? .critical : shown >= 70 ? .warn : .normal
    }
}

/// A session spending right now.
struct Burn: Identifiable {
    let id: String
    let name: String
    let model: String
    let perHour: Double
    /// Points of the 5-hour window per hour, once a cap is known.
    let pctPerHour: Double?
    /// Runs on Fable, the model with a limit of its own: its bar is pink.
    var fable = false
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
    /// The model of its last turn ("Opus 5.5"), for its mascot's colour.
    var model = ""
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

/// The Fable card: Anthropic's separate weekly Fable limit, and this Mac's Fable use.
struct FableView {
    /// The limit as last read, exact as of then. Nil when none is known for the week.
    var limit: WindowView?
    /// Claude Code's usage report lists no Fable limit: the plan has none, so Fable only counts in
    /// the overall limits.
    var noLimit = false
    /// This Mac's Fable spend in the open 5-hour window and this week, and as points of each window
    /// once its cap is known. Nil where the window isn't known.
    var fiveHourCost: Double?
    var fiveHourPts: Double?
    var weekCost: Double?
    var weekTokens = 0
    var weekPts: Double?
    var todayCost = 0.0
}

struct Snapshot {
    var loaded = false
    var fiveHour: WindowView?
    var weekly: WindowView?
    var extras: [WindowView] = []
    var fable: FableView?
    var calibrated = false
    var burning: [Burn] = []
    var runaways: [Runaway] = []
    var cooling: [Cooling] = []
    var weekShares: [Share] = []
    /// Weekly % the logs can't account for: claude.ai chat, the phone, other machines.
    var weekElsewhere: Double?
    /// This week at pay-as-you-go prices, for the weekly card's line and History.
    var weekValue: WeekValue?
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
    /// The shortcut's own message (keys taken by another app), apart from `notice`, so neither
    /// replaces the other.
    @Published var hotkeyNotice: String?

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
    private var historyFile: UInt64?
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
    /// What reads the usage report for the Fable limit; swappable like `probe`.
    var usage: () async -> Probe.UsageOutcome = { await Probe.usage() }
    private var fableRunning = false
    private var fableLaunched: Date?
    private var fableFailures = 0
    private var fableRetryAt: Date?

    private static let fiveHours: TimeInterval = 5 * 3600
    private static let week: TimeInterval = 7 * 86400
    private static let logSpan: TimeInterval = 8 * 86400
    private static let burnLookback: TimeInterval = 900
    /// An exact reading at most this often, and only after new activity.
    private static let probeEvery: TimeInterval = 60
    /// The usage report, for the Fable limit: this often while Fable is in use on this Mac, and while it isn't.
    private static let fableEveryBusy: TimeInterval = 300
    private static let fableEveryQuiet: TimeInterval = 1800
    /// The usage report this often while no 5-hour window is known to be open: it is what shows a window
    /// opened away from this Mac, and until one is seen the meter can't probe.
    private static let reportEveryIdle: TimeInterval = 300
    /// A single session using this much of the 5-hour window within 30 minutes is flagged.
    private static let runawayPct: Double = 20
    /// The cards' titles, which the alerts are also filed under.
    static let fiveHourTitle = "5-hour window"
    static let weeklyTitle = "Weekly · all models"
    static let fableTitle = "Weekly · Fable"
    /// Bump when the cost of a turn changes meaning, so calibration relearns instead of drifting.
    /// 2: the largest copy of each turn counts (0.8).
    /// Not for a price change on a model that is a sliver of the spend (Haiku 5.5 in 0.9.2 was 0.1% of
    /// the tokens, $1.44 against $3.71 over a week): relearning both caps would show for hours to fix
    /// a change smaller than their rounding.
    private static let costBasis = 2
    /// The weekly cap's own basis (bump it with `costBasis` too), bumped alone to relearn only it. 3: a stale drop-in faked an early reset
    /// on Oct 12 (see `absorb`), and counting the week from there taught a cap of $150 instead of four figures.
    private static let weekBasis = 3

    /// A 5-hour window opens at its first message rounded down to the 10-minute mark (every
    /// window in the history log starts on :x0:00, 0-9 minutes before its first message).
    private static func windowOpening(_ firstMessage: Date) -> Date {
        Date(timeIntervalSince1970: (firstMessage.timeIntervalSince1970 / 600).rounded(.down) * 600)
    }
    private static let blockedNotice =
        "Notifications are blocked for Claude Meter. Turn them on in the settings pane that just opened."
    private static let loadingNotice = "Still reading your Claude Code logs. Try Sync again in a moment."
    private static let noWindowNotice =
        "No 5-hour window is open, and a probe would start one. It will sync once one opens, here or elsewhere."

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
        // Not one dated in the future, which `absorb` turns away too.
        if reading.source == "tap", reading.at <= clock().addingTimeInterval(60) { store.state.tapSeen = reading.at }
        absorb(reading)
    }

    /// Runs the probe once a minute while a window is open, whether or not anything was logged here:
    /// use this Mac can't see (cloud sessions, claude.ai, the phone) moves it too, and a probe is a
    /// tiny Haiku turn. With no window open it waits for one to open: a message here, or a window the usage report lists
    /// (opened elsewhere). A probe would open one.
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
        refreshFable(force: force, now: now)
        guard windowOpen(now) else {
            if force { notice = Self.noWindowNotice }
            return
        }
        // A window is open now, so "none is open" from an earlier Sync no longer holds, whatever this
        // probe says, or whether one runs this tick at all.
        if notice == Self.noWindowNotice { notice = nil }
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
                absorb(reading)
            case .failed(let reason):
                // A minute at first, doubling to half an hour; a failure only you can fix (signed out,
                // no CLI) waits five minutes: such a probe fails at once and spends nothing, so the
                // wait only limits how often it starts, and you are noticed back soon after you log in.
                // One you fix doesn't count toward the doubling: once you've logged in, an ordinary failure
                // starts again from a minute.
                let needsYou = Probe.needsYou(reason)
                probeFailures = needsYou ? 0 : probeFailures + 1
                let wait = needsYou ? 300 : min(1800, 60 * pow(2, Double(probeFailures - 1)))
                store.state.probeError = reason
                store.state.probeRetryAt = clock().addingTimeInterval(wait)
            }
            store.save()
            recompute()
        }
    }

    /// Reads the separate weekly Fable limit from Claude Code's own usage report. The probe's limits
    /// don't carry it (they did for a week in September, filed as "Weekly · Fable"); `claude -p /usage`
    /// lists it, and being a local command it makes no model request, so it costs nothing and never
    /// opens a window, which is why it isn't behind the probe's window gate: Fable use on claude.ai or
    /// the phone moves it too. Every 5 minutes with Fable in use on this Mac or no window known to be open
    /// (the report's 5-hour line is how a window opened elsewhere is found), every 30 otherwise, at once
    /// when the held reading's week has ended, and on Sync whatever the timing. A failure waits a minute,
    /// doubling to half an hour, and that wait alone says when the next try is.
    private func refreshFable(force: Bool, now: Date) {
        guard !fableRunning else { return }
        if !force {
            if let retry = fableRetryAt, retry <= now.addingTimeInterval(3600) {
                guard now >= retry else { return }
            } else {
                // Timed from the last report read or the last launch, whichever is later; neither if it is
                // ahead of a clock that has since been put back.
                let checked = store.state.fableChecked.flatMap { $0 <= now.addingTimeInterval(60) ? $0 : nil }
                let launched = fableLaunched.flatMap { $0 <= now ? $0 : nil }
                if let since = [checked, launched].compactMap({ $0 }).max() {
                    // The held reading's week has ended and no report has been read since.
                    let lapsed = store.state.fable.map { now >= $0.resetsAt && (checked ?? .distantPast) < $0.resetsAt } ?? false
                    let busy = turns.reversed().prefix { now.timeIntervalSince($0.at) <= Self.burnLookback }.contains { $0.fable }
                    let every = busy ? Self.fableEveryBusy : !windowOpen(now) ? Self.reportEveryIdle : Self.fableEveryQuiet
                    guard lapsed || now.timeIntervalSince(since) >= every else { return }
                }
            }
        }
        let launched = clock()
        fableLaunched = launched
        fableRunning = true
        Task {
            let outcome = await usage()
            fableRunning = false
            switch outcome {
            case .limits(let limits):
                fableFailures = 0
                fableRetryAt = nil
                let wasOpen = windowOpen(clock())
                takeFable(limits, at: launched)
                // A window opened away from this Mac: probe now rather than at the next tick.
                if !wasOpen, windowOpen(clock()) {
                    store.save()
                    sync(force: false)
                }
            case .failed:
                fableFailures += 1
                fableRetryAt = clock().addingTimeInterval(min(1800, 60 * pow(2, Double(fableFailures - 1))))
            }
            store.save()
            recompute()
        }
    }

    /// Files the Fable limit from a usage report: the line named Fable, with its reset read from the text.
    /// The Fable week ends with the weekly window, and the report floors the Fable reset to the minute
    /// ("2:59pm" against the all-models week's "3pm", for the same moment), so a reset within a quarter
    /// hour of the weekly window's is that one, and the window's stands in when the text couldn't be read.
    /// A report with no Fable line among its limits is noted as a plan without the limit only when it can't
    /// be a report served from Claude Code's cache, which leaves the per-model limits out: when it lists another
    /// model's limit, when no Fable limit was ever read, or when a whole week has passed since the last one
    /// reset. Otherwise (just after the week rolled over, say) the Fable limit is not known yet rather than
    /// none. A reading still in its week is kept either way, and so is one whose new reset couldn't be placed.
    func takeFable(_ limits: [Probe.UsageLimit], at: Date) {
        store.state.fableChecked = at
        // The 5-hour line's reset, for the probe gate. The report prints it to the minute, floored, so the
        // real reset is that or a little later and the gate's margin still holds. No 5-hour window resets
        // more than five hours out, so a time read as tomorrow's (or a misread one) opens nothing.
        store.state.sessionResets = limits.first { $0.kind == "session" }?.resetsAt
            .flatMap { $0 > at && $0 <= at.addingTimeInterval(Self.fiveHours + 60) ? $0 : nil }
        guard let fable = limits.first(where: { $0.name.lowercased().contains("fable") }) else {
            let otherModel = limits.contains { $0.kind == "week" && !["week", "all models"].contains($0.name.lowercased()) }
            let hadOne = store.state.fable.map { at.timeIntervalSince($0.resetsAt) < Self.week } ?? false
            store.state.fableNone = otherModel || !hadOne ? at : nil
            return
        }
        store.state.fableNone = nil
        let held = (store.state.lastExact?.weekly?.resetsAt).flatMap { $0 > at ? $0 : nil }
        var resets = fable.resetsAt
        if let held, resets == nil || Window.same(resets, held) { resets = held }
        guard let resets, resets > at else { return }
        store.state.fable = Window(pct: fable.pct, resetsAt: resets, at: at).normalized
    }

    /// A probe is a request, and a request opens a 5-hour window if none is open, moving your
    /// reset. So only probe while a window is known to be open: the last reading's window hasn't
    /// reset (whether or not anything was logged here), the usage report lists a later one (opened
    /// away from this Mac), or a message went out after it did. With no reading to go on, the report's
    /// window or right after a message. Never in the last two minutes of any.
    func windowOpen(_ now: Date) -> Bool {
        // Not the last two minutes before any reset, measured or walked: a probe launched then can
        // reach the API after the reset and open the next window.
        func clearOfReset(_ opened: Date) -> Bool {
            now < opened.addingTimeInterval(Self.fiveHours - Self.resetMargin)
        }
        // The window the usage report lists, unless the last reading's is that one or a later one: a
        // report read before an early reset can still list the window it ended.
        let measured = store.state.lastExact?.fiveHour?.resetsAt
        if let listed = store.state.sessionResets, now < listed.addingTimeInterval(-Self.resetMargin),
           measured.map({ listed > $0.addingTimeInterval(Self.resetMargin) }) ?? true { return true }
        // The last reading's window first, with nothing logged here at all (use only elsewhere: cloud
        // sessions, claude.ai) as much as with.
        if let resets = measured {
            // A message after the reset opened a window, but that one ends too.
            if now < resets.addingTimeInterval(-Self.resetMargin) { return true }
            guard let opened = openWindow(after: resets, now: now) else { return false }
            return clearOfReset(opened)
        }
        // The window that message is in may have opened hours before it and be about to end.
        guard let first = turns.first?.at, let latest = turns.last?.at, now.timeIntervalSince(latest) < 600,
              let opened = openWindow(after: first, now: now) else { return false }
        return clearOfReset(opened)
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
            // Newer than what's held, unless the clock was set back since that was taken. Or a probe's,
            // which is dated when it was launched: a statusline reading taken in while it ran is newer, but
            // the probe measured its windows itself (a drop, an early reset, a Fable bucket the statusline
            // can't carry), so it goes through `pick` window by window rather than being thrown away.
            let probedMeanwhile = reading.source == "probe" && last.source != "probe"
                && last.at.timeIntervalSince(reading.at) <= Self.slowProbe
            guard reading.at > last.at || probedMeanwhile || last.at > now.addingTimeInterval(60) else { return }
            // Windows saved before they carried their own time were measured with their reading.
            func dated(_ w: Window?) -> Window? { w.map { var d = $0; d.at = d.at ?? last.at; return d } }
            var isFresh = false
            // Only the probe measures at its reading's time. Everything from tap.json (the statusline, and
            // Claude Dashboard relaying sessions' statuslines) is stamped when written and can carry an old
            // number: on Oct 12 the dashboard dropped in weekly 50% while the week was at 59%, which read
            // as an early reset and taught a weekly cap of $150.
            let measuredNow = reading.source == "probe"
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
        // A per-model bucket for Fable (the probe carried one for a week in September): the newest
        // reading of that limit there is, when this reading measured it itself.
        if let w = reading.extras.first(where: { $0.key.lowercased().contains("fable") })?.value,
           abs((w.at ?? reading.at).timeIntervalSince(reading.at)) < 1 {
            store.state.fable = Window(pct: w.pct, resetsAt: w.resetsAt, at: reading.at)
            store.state.fableChecked = reading.at
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
    /// measured at the reading's time (a probe), not carried by the statusline or a drop-in.
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
                // an old number re-sent, unless it fell to nothing from a point or more: a window reset
                // early while it was still small. Otherwise the window keeps any such reset it had.
                let toNothing = measuredNow && new.pct < 0.5 && old.pct >= 1
                if measuredNow, !toNothing, new.pct < old.pct - 0.5, new.pct >= old.pct - Self.restartDrop { return (old, false) }
                if new.pct < old.pct - Self.restartDrop || toNothing {
                    Self.markRestart(&new, after: old)
                } else {
                    new.restartedAt = old.restartedAt
                    new.restartedLate = old.restartedLate
                }
            } else if new.resetsAt.addingTimeInterval(-span) < old.resetsAt.addingTimeInterval(-60) {
                // A later window that began before the held one was due to reset (a window opens at
                // or after the last one's reset): Anthropic ended that one early. From any source: a
                // later window can't be an old number re-sent, so the statusline seeing it first counts.
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
        // (No later than the reading that saw it: a probe's, dated at its launch, can be older than a
        // statusline reading taken in while it ran.)
        new.restartedAt = min(last, seen)
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
            // (Not timed from a check dated ahead of the clock: it was set back since, and the spacing
            // would hold every check off until it caught up.)
            if let last = checks.last(where: { $0.window == name }), last.at <= clock().addingTimeInterval(60),
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
            c.capWeek = blend(c.basisWeek == Self.weekBasis ? c.capWeek : nil, cap, pct: w.pct)
            c.basisWeek = Self.weekBasis
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
            s.weekValue = weekValue(s, now: now)
            s.fable = fable(s, now: now)
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
            let fivePct = (f.exact ? "" : "~") + Fmt.pct(f.pct)
            var time: String?
            if let capAt = s.capWarning {
                time = "cap " + Fmt.bareClock(capAt) // within 5 hours, so no weekday or AM/PM: the title stays short
            } else if let r = f.resetsAt {
                time = Fmt.left(r.timeIntervalSince(now))
            }
            var title = fivePct + (time.map { " · " + $0 } ?? "")
            var level = max(f.level, s.capWarning != nil ? .warn : .normal)
            if showWeeklyInTitle, let w = s.weekly {
                // With the week, the 5-hour % is left to the ring, so the title fits beside the notch
                // (2026-10-19): "2h50m wk 41%", at most "cap 10:49 wk ~100%".
                title = (time ?? fivePct) + " wk " + (w.exact ? "" : "~") + Fmt.pct(w.pct)
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
            // Nothing has measured this window yet: its % is this Mac's spend alone, so it raises no alert.
            v.stale = true
        } else {
            // No cap yet to estimate with, but whether any window is open is still known.
            if let resets = last?.fiveHour?.resetsAt, now >= resets, openWindow(after: resets, now: now) == nil {
                return WindowView(title: Self.fiveHourTitle, pct: 0, exact: false, asOf: last?.at, idle: true)
            }
            return nil
        }

        if let cap, let resets = v.resetsAt {
            // 20+ minutes of pace before projecting: a window's first minutes are mostly cache
            // writes and would project a cap that isn't coming. Counted from an early reset, if any:
            // the spend before it no longer counts toward this window.
            project(&v, cap: cap, now: now, windowStart: Self.countsFrom(resets, span: Self.fiveHours, v.restartedAt),
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
            // Nothing has measured this week yet: if Anthropic reset it early, or the Mac slept across
            // the reset, its % is this Mac's spend alone, so it raises no alert.
            v.stale = true
        }

        if let cap, let resets = v.resetsAt {
            project(&v, cap: cap, now: now, windowStart: Self.countsFrom(resets, span: Self.week, v.restartedAt),
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
        let attributes = try? FileManager.default.attributesOfItem(atPath: Paths.history.path)
        let size = (attributes?[.size] as? NSNumber)?.uint64Value ?? 0
        let file = (attributes?[.systemFileNumber] as? NSNumber)?.uint64Value
        // Compacted or replaced: start over. A compaction writes a new file, so it shows as a new file
        // number even when it shrank by less than was appended since the last read.
        if size < historyEnd || file != historyFile {
            historyReadings = []
            historyEnd = 0
            historyFile = file
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

    /// Where a window's count begins: its start, or the early reset Anthropic started it again from.
    private static func countsFrom(_ resets: Date, span: TimeInterval, _ restartedAt: Date?) -> Date {
        max(resets.addingTimeInterval(-span), restartedAt ?? .distantPast)
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
    /// usage the logs never see) gives its height. A window Anthropic reset early climbs from its
    /// restart: the spend before that no longer counts, and is drawn flat at 0.
    private func series(_ v: inout WindowView, now: Date) {
        guard let resets = v.resetsAt, !v.idle else { return }
        let start = resets.addingTimeInterval(-Self.fiveHours)
        // A clock set back can put the window's start after now; there's nothing to draw then.
        guard start <= now else { return }
        let from = min(Self.countsFrom(resets, span: Self.fiveHours, v.restartedAt), now)
        let lower = first(atOrAfter: from)
        let upper = max(lower, first(atOrAfter: now.addingTimeInterval(1)))
        let inWindow = turns[lower..<upper]
        let total = inWindow.reduce(0) { $0 + $1.cost }
        var points = [PacePoint(at: start, pct: 0)]
        if from > start { points.append(PacePoint(at: from, pct: 0)) }
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
                  let first = turns.first(where: { $0.session == id }),
                  // Its first turn kept, near the edge of the 8 days the logs hold, may not be its first.
                  first.at > coveredFrom.addingTimeInterval(Self.fiveHours) else { return tag }
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
                        perHour: perHour, pctPerHour: cap.map { perHour / $0 * 100 }, fable: t.fable)
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
                           extraPct: cap.map { extra / $0 * 100 }, model: Fmt.model(t.model))
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

    /// The week so far at pay-as-you-go prices: this Mac's turns since the week counts from (as the
    /// project shares count), by day and model, and the weekly points the logs can't account for, in
    /// dollars at the weekly cap. Days are local days from the week's first to the reset's, so a 3 PM
    /// reset gives eight, the first and last partly. Days are this Mac's alone: split by the exact
    /// readings, elsewhere's daily parts went negative on real weeks (cloud use moves the cap).
    private func weekValue(_ s: Snapshot, now: Date) -> WeekValue? {
        guard let w = s.weekly, let resets = w.resetsAt, now < resets else { return nil }
        let begin = min(Self.countsFrom(resets, span: Self.week, w.restartedAt), now)
        var mac = 0.0
        var byModel: [String: Double] = [:]
        var names: [String: String] = [:]
        let a = first(atOrAfter: begin), b = first(atOrAfter: now)
        if b > a {
            for t in turns[a..<b] {
                mac += t.cost
                let name = names[t.model] ?? {
                    let n = Fmt.model(t.model)
                    names[t.model] = n
                    return n
                }()
                byModel[name, default: 0] += t.cost
            }
        }
        var v = WeekValue(begin: begin, resets: resets, mac: mac)
        if let points = s.weekElsewhere, let cap = store.state.calibration.capWeek {
            v.elsewhere = points * cap / 100
        }
        v.models = byModel.map { Row(id: $0.key, cost: $0.value, tokens: 0) }.sorted { $0.cost > $1.cost }
        let cal = Calendar.current
        var day = cal.startOfDay(for: resets.addingTimeInterval(-Self.week))
        while day < resets, let next = cal.date(byAdding: .day, value: 1, to: day) {
            let from = max(day, begin), to = min(next, now)
            v.days.append(ValueDay(day: day, mac: to > from ? cost(from: from, to: to) : 0,
                                   future: day > now, before: next <= begin))
            day = next
        }
        return v
    }

    // MARK: Fable

    /// The Fable card: the separate weekly Fable limit as last read, or that the plan has none, over
    /// this Mac's Fable use as a part of the overall windows. Nil when there is nothing to say: no
    /// limit known for the week and no Fable use on this Mac this week.
    private func fable(_ s: Snapshot, now: Date) -> FableView? {
        var f = FableView()
        if let w = store.state.fable, now < w.resetsAt {
            f.limit = WindowView(title: Self.fableTitle, pct: w.pct, resetsAt: w.resetsAt, exact: true, asOf: w.at)
        } else if let none = store.state.fableNone, none > (store.state.fable?.at ?? .distantPast) {
            // The last report listed limits but no Fable one, and no reading has come since.
            f.noLimit = true
        }
        let cal = store.state.calibration
        if let w = s.fiveHour, !w.idle, let resets = w.resetsAt {
            let spend = fableSpend(from: Self.countsFrom(resets, span: Self.fiveHours, w.restartedAt), to: now)
            f.fiveHourCost = spend.cost
            f.fiveHourPts = cal.cap5h.map { spend.cost / $0 * 100 }
        }
        // The week is the weekly window's (from an early reset, if it had one), or the Fable limit's own
        // when there is no weekly reading.
        if let end = s.weekly?.resetsAt ?? store.state.fable?.resetsAt, now < end {
            let spend = fableSpend(from: Self.countsFrom(end, span: Self.week, s.weekly?.restartedAt), to: now)
            f.weekCost = spend.cost
            f.weekTokens = spend.tokens
            f.weekPts = cal.capWeek.map { spend.cost / $0 * 100 }
        }
        f.todayCost = fableSpend(from: Calendar.current.startOfDay(for: now), to: now).cost
        let used = (f.weekCost ?? 0) > 0 || f.todayCost > 0
        return f.limit != nil || used ? f : nil
    }

    /// This Mac's Fable turns in a span: their $-equivalent and tokens.
    private func fableSpend(from: Date, to: Date) -> (cost: Double, tokens: Int) {
        var cost = 0.0, tokens = 0
        let a = first(atOrAfter: from), b = first(atOrAfter: to)
        guard b > a else { return (0, 0) }
        for t in turns[a..<b] where t.fable {
            cost += t.cost
            tokens += t.tokens
        }
        return (cost, tokens)
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

        // The latest exact reading of each window, keyed by the minute it resets. A reset reported a
        // minute or so apart (two sources, rounding) is the same window, as everywhere else
        // (`Window.same`): it joins the key already there rather than drawing a window of its own.
        // `top` is the highest it was measured at: a window Anthropic reset early under the same reset
        // time still peaked there before the drop.
        func key(_ d: Date) -> Int { Int((d.timeIntervalSince1970 / 60).rounded()) }
        // `restart` is the early reset its latest reading carries, if Anthropic reset it under the same time.
        var latestExact: [Int: (pct: Double, at: Date, top: Double, restart: Date?)] = [:]
        for r in readings {
            guard let w = r.fiveHour else { continue }
            let at = w.at ?? r.at
            let k = key(w.resetsAt)
            let slot = latestExact.keys.first { abs($0 - k) <= 15 } ?? k
            let top = max(latestExact[slot]?.top ?? 0, w.pct)
            if let held = latestExact[slot], held.at >= at {
                latestExact[slot]?.top = top
                continue
            }
            latestExact[slot] = (w.pct, at, top, w.restartedAt)
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
            // Past its last reading a window is extended at its own rate (its spend up to that reading per
            // point it measured), not today's cap: the cap moves with how much was used off this Mac, and
            // a window from days ago drawn with today's would peak above what its readings say.
            // Its own rate only from as much as calibration would learn a cap from (10% and $0.50 behind
            // it), and only from the spend since an early reset: a few points over a little spend would
            // carry what was logged after it far past the cap. Short of that, today's cap.
            func peak(_ start: Date, _ end: Date, reset: Date) -> (Double, Bool) {
                if let e = latestExact[key(reset)] {
                    let before = cost(from: max(start, e.restart ?? .distantPast), to: e.at)
                    let own = e.pct >= 10 && before > 0.5 ? before / (e.pct / 100) : cap
                    return (max(e.top, e.pct + cost(from: e.at, to: min(end, now)) / own * 100), true)
                }
                return (cost(from: start, to: min(end, now)) / cap * 100, false)
            }
            var drawn: [Date] = [] // the resets a window has been drawn for
            // Walk the windows forward from the start of the logs, so their edges are the real
            // ones (each opens at the first message after the last closed, rounded down to 10
            // minutes), snapped to the real window where an exact reading pins one down.
            var anchor = turns.first.map { Self.windowOpening($0.at) } ?? since
            // The first turn kept can sit mid-window (the 8-day trim cut off its start), which would shift
            // every window after it. Begin instead at a message after five quiet hours, which certainly
            // opened one, or at a window a reading pins down, if one comes before the week drawn.
            if let first = turns.first?.at, first < since {
                if let i = turns.indices.dropFirst().first(where: {
                    turns[$0].at <= since && turns[$0].at.timeIntervalSince(turns[$0 - 1].at) >= Self.fiveHours
                }) {
                    anchor = Self.windowOpening(turns[i].at)
                } else if let pinned = spans.first(where: { $0.start <= since })?.start {
                    anchor = pinned
                }
            }
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
                h.weekRateIsAverage = true
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
            // Nothing logged here since then (all of it used elsewhere): a straight climb to the %, not
            // a flat line that jumps at the end.
            func climb(_ t: Date) -> Double {
                guard logged <= 0 else { return cost(from: from, to: t) / cap * 100 * scale }
                let span = now.timeIntervalSince(from)
                return span > 0 ? w.pct * max(0, t.timeIntervalSince(from)) / span : 0
            }
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
                                                               : climb(t)))
                t.addTimeInterval(3600)
            }
            if let restart, h.weekSeries.last.map({ $0.at < restart }) ?? true {
                h.weekSeries.append(PacePoint(at: restart, pct: cost(from: start, to: restart) / cap * 100 * preScale))
                h.weekSeries.append(PacePoint(at: restart.addingTimeInterval(1), pct: 0))
            }
            h.weekSeries.append(PacePoint(at: now, pct: w.pct))
        }

        h.value = snapshot.weekValue

        let peak = h.windows.map(\.peak).max() ?? 0
        // No projection yet: the card says so ("–") rather than passing off the % so far as the % at reset.
        let week = h.weekAtReset
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
