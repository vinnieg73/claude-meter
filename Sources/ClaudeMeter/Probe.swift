import Foundation

/// Runs one tiny headless Claude Code turn (Haiku, no tools, a one-line system prompt, no saved
/// session) and reads the plan limits Claude Code reports alongside it. About $0.002 of usage.
/// Claude Code owns its login; this app never reads the token.
enum Probe {
    enum Outcome {
        case reading(ExactReading)
        case failed(String)
    }

    static func run() async -> Outcome {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async { continuation.resume(returning: runNow()) }
        }
    }

    private static func runNow() -> Outcome {
        guard let claude = binary() else { return .failed("Claude Code CLI not found") }
        // An empty folder, so no CLAUDE.md or project settings load.
        let dir = Paths.support.appendingPathComponent("probe")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = claude
        process.arguments = [
            "-p", "ok", "--model", "haiku",
            "--system-prompt", "Reply with the single word ok.",
            "--tools", "", "--strict-mcp-config", "--no-session-persistence",
            "--output-format", "stream-json", "--verbose",
        ]
        process.currentDirectoryURL = dir
        var env = ProcessInfo.processInfo.environment
        // Any of these would move the call off the subscription (the desktop app sets the first).
        for key in ["ANTHROPIC_BASE_URL", "ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN"] { env[key] = nil }
        process.environment = env
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let out = Pipe()
        process.standardOutput = out

        do { try process.run() } catch { return .failed("couldn't start Claude Code") }
        let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 60, execute: timeout)
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timeout.cancel()
        return parse(data)
    }

    static var cliPath: String? { binary()?.path }

    /// Apps don't see the shell's PATH, so look where the installers put it.
    private static func binary() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["\(home)/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    /// Looks for the `rate_limit_event` in Claude Code's stream-json output. Its
    /// `unifiedWindows` carry utilization as a fraction and resets as epoch seconds.
    static func parse(_ data: Data) -> Outcome {
        var reading: ExactReading?
        var error: String?
        for line in data.split(separator: 0x0A) {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else { continue }
            switch obj["type"] as? String {
            case "rate_limit_event":
                guard let info = obj["rate_limit_info"] as? [String: Any],
                      let windows = info["unifiedWindows"] as? [String: Any] else { continue }
                var r = ExactReading(at: Date(), source: "probe")
                for (key, value) in windows {
                    guard let w = value as? [String: Any],
                          let used = (w["utilization"] as? NSNumber)?.doubleValue,
                          let resets = (w["resetsAt"] as? NSNumber)?.doubleValue else { continue }
                    let window = Window(pct: used * 100, resetsAt: Date(timeIntervalSince1970: resets))
                    switch key {
                    case "five_hour": r.fiveHour = window
                    case "seven_day": r.weekly = window
                    default: r.extras[label(key)] = window
                    }
                }
                if r.fiveHour != nil || r.weekly != nil { reading = r }
            case "result":
                if obj["is_error"] as? Bool == true { error = obj["result"] as? String }
            default:
                continue
            }
        }
        if let reading { return .reading(reading) }
        if let error {
            let lower = error.lowercased()
            if lower.contains("login") || lower.contains("authenticat") {
                return .failed("Claude Code is signed out; run claude /login")
            }
            return .failed(String(error.prefix(80)))
        }
        return .failed("no limits reported; is Claude Code signed in to your subscription?")
    }

    /// "seven_day_opus" -> "Weekly · Opus"
    private static func label(_ key: String) -> String {
        let name = key.replacingOccurrences(of: "seven_day_", with: "")
            .replacingOccurrences(of: "_", with: " ").capitalized
        return "Weekly · \(name)"
    }
}
