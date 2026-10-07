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

    /// Sources disagree by seconds on the same reset (18:59:59.5 vs 19:00:00), and an estimated
    /// window by a few minutes, so two resets this close are the same window.
    static func same(_ a: Date?, _ b: Date?) -> Bool {
        guard let a, let b else { return a == nil && b == nil }
        return abs(a.timeIntervalSince(b)) < 900
    }

    /// The reset on the minute it means.
    var normalized: Window {
        Window(pct: pct, resetsAt: Date(timeIntervalSince1970: (resetsAt.timeIntervalSince1970 / 60).rounded() * 60),
               at: at, restartedAt: restartedAt)
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

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lastExact = try? c.decodeIfPresent(ExactReading.self, forKey: .lastExact)
        checks = try? c.decodeIfPresent([Check].self, forKey: .checks)
        calibration = (try? c.decodeIfPresent(Calibration.self, forKey: .calibration)) ?? Calibration()
        probeError = try? c.decodeIfPresent(String.self, forKey: .probeError)
        probeRetryAt = try? c.decodeIfPresent(Date.self, forKey: .probeRetryAt)
        tapSeen = try? c.decodeIfPresent(Date.self, forKey: .tapSeen)
        notified = (try? c.decodeIfPresent([String].self, forKey: .notified)) ?? []
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
            guard let date = frac.date(from: s) ?? whole.date(from: s) else {
                throw DecodingError.dataCorruptedError(in: c, debugDescription: "not an ISO 8601 date: \(s)")
            }
            return date
        }
        return d
    }
}

enum Paths {
    static let support: URL = {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClaudeMeter")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()
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
        if let data = try? Data(contentsOf: Paths.state) {
            if let saved = try? JSONCoding.decoder().decode(PersistedState.self, from: data) {
                state = saved
            } else {
                state = PersistedState()
                unreadable = true
            }
        } else {
            state = PersistedState()
        }
        let now = Date()
        // A reading dated in the future would block every later one; drop it and take a new one.
        if let at = state.lastExact?.at, at > now.addingTimeInterval(60) { state.lastExact = nil }
        if let at = state.calibration.updatedAt, at > now.addingTimeInterval(60) { state.calibration.updatedAt = nil }
        if let at = state.probeRetryAt, at > now.addingTimeInterval(3600) { state.probeRetryAt = nil }
        pruneNotified()
    }

    /// Notification keys carry the window's reset epoch; old windows can go.
    func pruneNotified() {
        let cutoff = Date().addingTimeInterval(-8 * 86400).timeIntervalSince1970
        state.notified.removeAll { key in
            let parts = key.split(separator: "|")
            return parts.count > 1 && (Double(parts[1]) ?? 0) < cutoff
        }
    }

    func save() {
        guard !readOnly, let data = try? JSONCoding.encoder(pretty: true).encode(state) else { return }
        if unreadable {
            let stamp = Int(Date().timeIntervalSince1970)
            try? FileManager.default.moveItem(at: Paths.state,
                                              to: Paths.support.appendingPathComponent("state.unreadable-\(stamp).json"))
            unreadable = false
        }
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
