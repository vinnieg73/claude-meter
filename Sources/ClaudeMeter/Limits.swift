import Foundation

/// A plan-limit window as Anthropic reports it.
struct Window: Codable {
    var pct: Double
    var resetsAt: Date
}

/// An exact reading of the plan limits, from whichever source had one.
struct ExactReading: Codable {
    var at: Date
    /// "tap" (Claude Code statusline), "api" (the OAuth usage endpoint), "app" (read from the desktop app)
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
    var apiNextAllowed: Date?
    var apiStatus: String?
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

/// The endpoint behind Claude Code's /usage. Undocumented, and rate-limited hard
/// (a 429 carries retry-after: 3600), so it is asked at most hourly.
enum UsageAPI {
    enum Outcome {
        case reading(ExactReading)
        case retryAfter(TimeInterval)
        case failed(String)
    }

    static func fetch() async -> Outcome {
        guard let token = accessToken() else { return .failed("no Claude Code token in Keychain") }
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("claude-meter/0.1", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let http = response as? HTTPURLResponse
            switch http?.statusCode ?? 0 {
            case 200:
                guard let reading = parse(data) else { return .failed("unreadable response") }
                return .reading(reading)
            case 401, 403:
                return .failed("Claude Code CLI login expired; run claude /login")
            case 429:
                let retry = Double(http?.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 3600
                return .retryAfter(retry)
            case let code:
                return .failed("HTTP \(code)")
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Claude Code stores its login in the Keychain via /usr/bin/security, so asking
    /// through the same tool reads it without a prompt. The token only goes to Anthropic.
    private static func accessToken() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        do { try process.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = obj["claudeAiOauth"] as? [String: Any] else { return nil }
        return oauth["accessToken"] as? String
    }

    /// Any top-level object with a `utilization` is a window; unknown ones become extras.
    private static func parse(_ data: Data) -> ExactReading? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        var reading = ExactReading(at: Date(), source: "api")
        for (key, value) in obj {
            guard let w = value as? [String: Any],
                  let pct = (w["utilization"] as? NSNumber)?.doubleValue,
                  let resets = date(w["resets_at"]) else { continue }
            let window = Window(pct: pct, resetsAt: resets)
            switch key {
            case "five_hour": reading.fiveHour = window
            case "seven_day": reading.weekly = window
            default:
                let name = key.replacingOccurrences(of: "seven_day_", with: "")
                    .replacingOccurrences(of: "_", with: " ").capitalized
                reading.extras["Weekly · \(name)"] = window
            }
        }
        return reading.fiveHour == nil && reading.weekly == nil ? nil : reading
    }

    private static func date(_ value: Any?) -> Date? {
        if let n = value as? NSNumber { return Date(timeIntervalSince1970: n.doubleValue) }
        guard let s = value as? String else { return nil }
        let frac = ISO8601DateFormatter()
        frac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return frac.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }
}
