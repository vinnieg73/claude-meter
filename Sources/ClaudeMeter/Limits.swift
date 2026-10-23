import Foundation

/// A plan-limit window as Anthropic reports it.
struct Window: Codable {
    var pct: Double
    var resetsAt: Date
    /// When this window's % was measured. A reading can carry a window forward from an
    /// earlier one, so the reading's own time isn't always this window's.
    var at: Date?
    /// When Anthropic reset this window's usage before its reset time (it did on Oct 7: the weekly
    /// went from 87% to 0 with the same Wednesday reset), as near as the readings can tell: the last
    /// higher measurement. From then its % no longer counts from the window's start.
    var restartedAt: Date?
    /// The reset wasn't noticed until long after (nothing was measuring in between), so
    /// `restartedAt` is when it was seen, not when it happened, and the window can't teach a cap.
    var restartedLate: Bool?

    /// Sources disagree by seconds on the same reset (18:59:59.5 vs 19:00:00), and an estimated
    /// window by a few minutes, so two resets this close are the same window.
    static func same(_ a: Date?, _ b: Date?) -> Bool {
        guard let a, let b else { return a == nil && b == nil }
        return abs(a.timeIntervalSince(b)) < 900
    }

    /// The reset on the minute it means.
    var normalized: Window {
        Window(pct: pct, resetsAt: Date(timeIntervalSince1970: (resetsAt.timeIntervalSince1970 / 60).rounded() * 60),
               at: at, restartedAt: restartedAt, restartedLate: restartedLate)
    }
}

/// An exact reading of the plan limits, from whichever source had one.
struct ExactReading: Codable {
    var at: Date
    /// "probe" (a headless Claude Code turn), "tap" (Claude Code statusline), "app" (read from the desktop app)
    var source: String
    var fiveHour: Window?
    var weekly: Window?
    /// Per-model weekly buckets, keyed by label ("Weekly · Fable").
    var extras: [String: Window] = [:]

    init(at: Date, source: String, fiveHour: Window? = nil, weekly: Window? = nil, extras: [String: Window] = [:]) {
        self.at = at
        self.source = source
        self.fiveHour = fiveHour
        self.weekly = weekly
        self.extras = extras
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        at = try c.decode(Date.self, forKey: .at)
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? "unknown"
        fiveHour = try c.decodeIfPresent(Window.self, forKey: .fiveHour)
        weekly = try c.decodeIfPresent(Window.self, forKey: .weekly)
        extras = try c.decodeIfPresent([String: Window].self, forKey: .extras) ?? [:]
    }
}

/// $-equivalent spend that equals 100% of a window, learned from exact readings.
struct Calibration: Codable {
    var cap5h: Double?
    var capWeek: Double?
    var updatedAt: Date?
    /// How turns were costed when each cap was learned (`Meter.costBasis`). A cap learned
    /// under older costing is replaced, not blended, by the next reading.
    var basis5h: Int?
    var basisWeek: Int?
}

/// What the meter was showing when an exact reading arrived.
struct Check: Codable {
    var at: Date
    /// "5h" or "week"
    var window: String
    var estimated: Double
    var exact: Double
    var minutesSinceExact: Double
    /// The reading the estimate was made from (a state file from before this has none).
    var anchor: Double?
}

/// Every field optional on the way in, so a state file from an older or newer version still
/// loads instead of being replaced by an empty one.
struct PersistedState: Codable {
    var lastExact: ExactReading?
    var checks: [Check]?
    var calibration = Calibration()
    /// Set when the last probe failed: why, and when to try again.
    var probeError: String?
    var probeRetryAt: Date?
    var tapSeen: Date?
    var notified: [String] = []
    /// The separate weekly Fable limit, as Claude Code's usage report last listed it (the probe's limits
    /// don't carry it); when that report was last read, whatever it held; and when it last listed limits
    /// but no Fable one, in a report that can't have been served from Claude Code's cache (which leaves the
    /// per-model limits out): the plan has no Fable limit.
    var fable: Window?
    var fableChecked: Date?
    var fableNone: Date?
    /// The 5-hour reset the usage report last listed ("Current session: … resets …"), nil when it listed
    /// none. The report counts use from everywhere and opens no window, so it is how the meter learns a
    /// window was opened away from this Mac (a cloud session, claude.ai) and that a probe is safe.
    var sessionResets: Date?
    /// A field was there but wouldn't read, so it fell back to its default. Not saved: it tells the
    /// store to set the file aside before writing the rest back over it.
    var damaged = false

    enum CodingKeys: String, CodingKey {
        case lastExact, checks, calibration, probeError, probeRetryAt, tapSeen, notified, fable, fableChecked, fableNone, sessionResets
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var bad = false
        func field<T: Decodable>(_ type: T.Type, _ key: CodingKeys) -> T? {
            do { return try c.decodeIfPresent(type, forKey: key) } catch { bad = true; return nil }
        }
        lastExact = field(ExactReading.self, .lastExact)
        checks = field([Check].self, .checks)
        calibration = field(Calibration.self, .calibration) ?? Calibration()
        probeError = field(String.self, .probeError)
        probeRetryAt = field(Date.self, .probeRetryAt)
        tapSeen = field(Date.self, .tapSeen)
        notified = field([String].self, .notified) ?? []
        fable = field(Window.self, .fable)
        fableChecked = field(Date.self, .fableChecked)
        fableNone = field(Date.self, .fableNone)
        sessionResets = field(Date.self, .sessionResets)
        damaged = bad
    }
}

/// JSON with dates to the millisecond. Whole-second dates made a re-read reading look newer
/// than its saved copy.
enum JSONCoding {
    private static let frac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let whole = ISO8601DateFormatter()

    static func encoder(pretty: Bool = false) -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(frac.string(from: date))
        }
        if pretty { e.outputFormatting = [.prettyPrinted, .sortedKeys] }
        return e
    }

    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let s = try c.decode(String.self)
            guard let date = parseDate(s) else {
                throw DecodingError.dataCorruptedError(in: c, debugDescription: "not an ISO 8601 date: \(s)")
            }
            return date
        }
        return d
    }

    static func parseDate(_ s: String) -> Date? {
        fastDate(s) ?? frac.date(from: s) ?? whole.date(from: s)
    }

    /// "2026-10-07T04:28:09.123Z" (the fraction optional), the one form this app writes. By hand
    /// because the formatter takes ~50 us a date, a row of the history log has five, and a month
    /// of readings is tens of thousands of rows. Anything else (an offset, a malformed date)
    /// returns nil and goes to the formatters.
    static func fastDate(_ s: String) -> Date? {
        var s = s
        return s.withUTF8 { u -> Date? in
            guard u.count >= 20, u[4] == 45, u[7] == 45, u[10] == 84, u[13] == 58, u[16] == 58 else { return nil }
            func digits(_ at: Int, _ n: Int) -> Int? {
                var v = 0
                for i in at..<(at + n) {
                    let d = Int(u[i]) - 48
                    guard (0...9).contains(d) else { return nil }
                    v = v * 10 + d
                }
                return v
            }
            guard let year = digits(0, 4), let month = digits(5, 2), let day = digits(8, 2),
                  let hour = digits(11, 2), let minute = digits(14, 2), let second = digits(17, 2),
                  (1...12).contains(month), hour < 24, minute < 60, second < 60 else { return nil }
            var i = 19
            var millis = 0
            if u[i] == 46 {
                i += 1
                var places = 0
                while i < u.count, u[i] >= 48, u[i] <= 57 {
                    if places < 3 { millis = millis * 10 + Int(u[i]) - 48; places += 1 }
                    i += 1
                }
                guard places > 0 else { return nil }
                while places < 3 { millis *= 10; places += 1 }
            }
            guard i == u.count - 1, u[i] == 90 else { return nil }
            let leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
            let lengths = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
            guard (1...lengths[month - 1]).contains(day) else { return nil }
            // Days since 1970-01-01 (Howard Hinnant's days_from_civil).
            let y = month <= 2 ? year - 1 : year
            let era = (y >= 0 ? y : y - 399) / 400
            let yoe = y - era * 400
            let doy = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
            let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
            let days = era * 146097 + doe - 719468
            let whole = days * 86400 + hour * 3600 + minute * 60 + second
            return Date(timeIntervalSince1970: Double(whole) + Double(millis) / 1000)
        }
    }
}

enum Paths {
    static let support: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("ClaudeMeter")
    /// Made by whatever writes there, not by looking: a read-only run (the replay, --status) leaves no folder behind.
    static func makeSupport() {
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
    }
    static var state: URL { support.appendingPathComponent("state.json") }
    static var tap: URL { support.appendingPathComponent("tap.json") }
    static var history: URL { support.appendingPathComponent("history.jsonl") }
}

final class StateStore {
    var state: PersistedState
    /// For `--render` and `--status`: look, never write over the running app's state.
    var readOnly = false

    /// The state file couldn't be read; it's set aside (not overwritten) at the first save.
    private var unreadable = false

    init() {
        do {
            let data = try Data(contentsOf: Paths.state)
            if let saved = try? JSONCoding.decoder().decode(PersistedState.self, from: data) {
                state = saved
                // What read is kept; the file as it was is set aside at the first save, not overwritten.
                unreadable = saved.damaged
            } else {
                state = PersistedState()
                unreadable = true
            }
        } catch {
            state = PersistedState()
            // No file yet is a first launch. Any other failure (a permission, a disk error) is a file
            // that's there but couldn't be read: set it aside at the first save, don't overwrite it.
            let missing = (error as NSError).domain == NSCocoaErrorDomain
                && (error as NSError).code == NSFileReadNoSuchFileError
            unreadable = !missing
        }
        let now = Date()
        // A reading dated in the future would block every later one; drop it and take a new one.
        if let at = state.lastExact?.at, at > now.addingTimeInterval(60) { state.lastExact = nil }
        if let at = state.calibration.updatedAt, at > now.addingTimeInterval(60) { state.calibration.updatedAt = nil }
        if let at = state.probeRetryAt, at > now.addingTimeInterval(3600) { state.probeRetryAt = nil }
        if let at = state.fableChecked, at > now.addingTimeInterval(60) { state.fableChecked = nil }
        if let at = state.fableNone, at > now.addingTimeInterval(60) { state.fableNone = nil }
        if let at = state.fable?.at, at > now.addingTimeInterval(60) { state.fable = nil }
        // No 5-hour window resets more than five hours out.
        if let at = state.sessionResets, at > now.addingTimeInterval(5 * 3600 + 60) { state.sessionResets = nil }
        // A check dated ahead of the clock would hold off new checks for its window until the clock caught up.
        state.checks?.removeAll { $0.at > now.addingTimeInterval(60) }
        pruneNotified()
    }

    /// Notification keys carry the window's reset epoch; old windows can go.
    func pruneNotified(now: Date = Date()) {
        let cutoff = now.addingTimeInterval(-8 * 86400).timeIntervalSince1970
        state.notified.removeAll { key in
            let parts = key.split(separator: "|")
            return parts.count > 1 && (Double(parts[1]) ?? 0) < cutoff
        }
    }

    func save() {
        guard !readOnly, let data = try? JSONCoding.encoder(pretty: true).encode(state) else { return }
        if unreadable {
            let stamp = Int(Date().timeIntervalSince1970)
            do {
                try FileManager.default.moveItem(at: Paths.state,
                                                 to: Paths.support.appendingPathComponent("state.unreadable-\(stamp).json"))
            } catch {
                // Couldn't set it aside: leave it be rather than write over it.
                if FileManager.default.fileExists(atPath: Paths.state.path) { return }
            }
            unreadable = false
        }
        Paths.makeSupport()
        try? data.write(to: Paths.state, options: .atomic)
    }
}

/// Reads what claude-meter-tap saved from Claude Code's statusline input. Anything else
/// holding an exact reading can drop one here too, naming itself in `source`.
enum TapFile {
    static func read() -> ExactReading? {
        guard let data = try? Data(contentsOf: Paths.tap),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawAt = (obj["at"] as? NSNumber)?.doubleValue,
              let limits = obj["rate_limits"] as? [String: Any] else { return nil }

        // Seconds or milliseconds, kept to the millisecond as state is saved: finer than that,
        // the same reading would look newer than its saved copy after every relaunch.
        func seconds(_ value: Double) -> Double { ((value > 1e11 ? value / 1000 : value) * 1000).rounded(.down) / 1000 }
        func window(_ key: String) -> Window? {
            guard let w = limits[key] as? [String: Any],
                  let pct = (w["used_percentage"] as? NSNumber)?.doubleValue,
                  let resets = (w["resets_at"] as? NSNumber)?.doubleValue else { return nil }
            return Window(pct: pct, resetsAt: Date(timeIntervalSince1970: seconds(resets)))
        }
        let source = obj["source"] as? String ?? "tap"
        let reading = ExactReading(at: Date(timeIntervalSince1970: seconds(rawAt)), source: source,
                                   fiveHour: window("five_hour"), weekly: window("seven_day"))
        return reading.fiveHour == nil && reading.weekly == nil ? nil : reading
    }
}
