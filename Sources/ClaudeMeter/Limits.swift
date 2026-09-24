import Foundation

/// A plan-limit window as Anthropic reports it.
struct Window: Codable {
    var pct: Double
    var resetsAt: Date
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
}

/// $-equivalent spend that equals 100% of a window, learned from exact readings.
struct Calibration: Codable {
    var cap5h: Double?
    var capWeek: Double?
    var updatedAt: Date?
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

struct PersistedState: Codable {
    var lastExact: ExactReading?
    /// Optional so a state file written before checks existed still decodes.
    var checks: [Check]?
    var calibration = Calibration()
    /// Set when the last probe failed: why, and when to try again.
    var probeError: String?
    var probeRetryAt: Date?
    var tapSeen: Date?
    var notified: [String] = []
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
}

final class StateStore {
    var state: PersistedState

    init() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: Paths.state),
           let saved = try? decoder.decode(PersistedState.self, from: data) {
            state = saved
        } else {
            state = PersistedState()
        }
        // Notification keys end in the window's reset epoch; old windows can go.
        let cutoff = Date().addingTimeInterval(-8 * 86400).timeIntervalSince1970
        state.notified.removeAll { key in
            let parts = key.split(separator: "|")
            return parts.count > 1 && (Double(parts[1]) ?? 0) < cutoff
        }
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(state) {
            try? data.write(to: Paths.state, options: .atomic)
        }
    }
}

/// Reads what claude-meter-tap saved from Claude Code's statusline input. Anything else
/// holding an exact reading can drop one here too, naming itself in `source`.
enum TapFile {
    static func read() -> ExactReading? {
        guard let data = try? Data(contentsOf: Paths.tap),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let at = obj["at"] as? Double,
              let limits = obj["rate_limits"] as? [String: Any] else { return nil }

        func window(_ key: String) -> Window? {
            guard let w = limits[key] as? [String: Any],
                  let pct = w["used_percentage"] as? Double,
                  let resets = w["resets_at"] as? Double else { return nil }
            return Window(pct: pct, resetsAt: Date(timeIntervalSince1970: resets))
        }
        let source = obj["source"] as? String ?? "tap"
        let reading = ExactReading(at: Date(timeIntervalSince1970: at), source: source,
                                   fiveHour: window("five_hour"), weekly: window("seven_day"))
        return reading.fiveHour == nil && reading.weekly == nil ? nil : reading
    }
}
