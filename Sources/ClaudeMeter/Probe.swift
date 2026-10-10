import Foundation

/// Runs one tiny headless Claude Code turn (Haiku, no tools, a one-line system prompt, no saved
/// session, none of your settings or hooks) and reads the plan limits Claude Code reports
/// alongside it. About $0.001 of usage. Claude Code owns its login; this app never reads it.
enum Probe {
    enum Outcome {
        case reading(ExactReading)
        case failed(String)
    }

    private static let signedOut = "Claude Code is signed out; run claude /login"
    private static let notFound = "Claude Code CLI not found"
    private static let couldntStart = "couldn't start Claude Code"

    /// A failure that waiting won't fix: nothing is signed in, or there is no CLI to run. Anything
    /// else (offline, a slow machine, a token refreshing) is worth trying again soon.
    static func needsYou(_ reason: String) -> Bool {
        reason == signedOut || reason == notFound || reason == couldntStart
    }

    static func run() async -> Outcome {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async { continuation.resume(returning: runNow()) }
        }
    }

    private static func runNow() -> Outcome {
        guard let claude = binary() else { return .failed(notFound) }
        // An empty folder, so no CLAUDE.md or project settings load.
        let dir = Paths.support.appendingPathComponent("probe")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = claude
        process.arguments = [
            "-p", "ok", "--model", "haiku",
            "--system-prompt", "Reply with the single word ok.",
            "--tools", "", "--strict-mcp-config", "--no-session-persistence",
            // Your own settings would run your hooks (a "done" sound, say) on every probe.
            "--setting-sources", "", "--settings", #"{"disableAllHooks":true}"#,
            "--output-format", "stream-json", "--verbose",
        ]
        process.currentDirectoryURL = dir
        var env = ProcessInfo.processInfo.environment
        // Any of these would move the call off the subscription (the desktop app sets ANTHROPIC_BASE_URL):
        // an API key or endpoint, or Bedrock, Vertex or Foundry and their settings.
        for key in env.keys where key.hasPrefix("ANTHROPIC_") || key.hasPrefix("CLAUDE_CODE_USE_")
            || key == "AWS_BEARER_TOKEN_BEDROCK" { env[key] = nil }
        if let dir = ShellEnv.claudeConfigDir { env["CLAUDE_CONFIG_DIR"] = dir }
        // Apps launched from Finder or at login get a bare PATH; an npm-installed claude is a
        // node script and needs node on it.
        env["PATH"] = (searchDirs() + [env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"]).joined(separator: ":")
        process.environment = env
        process.standardInput = FileHandle.nullDevice

        // Read as output arrives and stop at end of file, or shortly after claude exits if a
        // child it left behind keeps the pipe open.
        let output = Buffer(), errors = Buffer()
        let finished = DispatchSemaphore(value: 0)
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        out.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                finished.signal()
            } else {
                output.append(chunk)
            }
        }
        err.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty { handle.readabilityHandler = nil } else { errors.append(chunk) }
        }
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }

        do { try process.run() } catch { return .failed(couldntStart) }
        let timedOut = exited.wait(timeout: .now() + 60) == .timedOut
        if timedOut {
            // Its children too, found now: once claude dies they belong to launchd.
            let children = descendants(of: process.processIdentifier)
            process.terminate()
            children.forEach { kill($0, SIGTERM) }
            if exited.wait(timeout: .now() + 5) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = exited.wait(timeout: .now() + 2)
            }
            children.forEach { kill($0, SIGKILL) }
        }
        _ = finished.wait(timeout: .now() + 2)
        out.fileHandleForReading.readabilityHandler = nil
        err.fileHandleForReading.readabilityHandler = nil

        var outcome = parse(output.data)
        if timedOut, case .failed(let reason) = outcome, reason == Self.silent {
            outcome = .failed("Claude Code didn't answer within a minute (offline?)")
        }
        // Nothing usable and nothing said why: pass on what claude wrote to stderr.
        if case .failed(let reason) = outcome, reason == Self.silent,
           let line = String(decoding: errors.data, as: UTF8.self)
               .split(separator: "\n").last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            return .failed(String(line.prefix(100)))
        }
        return outcome
    }

    /// Every process under `pid`, children first found, then theirs.
    private static func descendants(of pid: pid_t) -> [pid_t] {
        var found: [pid_t] = []
        var pending = [pid]
        while let parent = pending.popLast() {
            var buffer = [pid_t](repeating: 0, count: 256)
            guard proc_listchildpids(parent, &buffer, Int32(buffer.count * MemoryLayout<pid_t>.size)) > 0 else { continue }
            let children = buffer.filter { $0 > 0 }
            found += children
            pending += children
        }
        return found
    }

    /// Output collected from a pipe's handler thread.
    private final class Buffer: @unchecked Sendable {
        private let lock = NSLock()
        private var buffer = Data()
        func append(_ chunk: Data) { lock.lock(); buffer.append(chunk); lock.unlock() }
        var data: Data { lock.lock(); defer { lock.unlock() }; return buffer }
    }

    static var cliPath: String? { binary()?.path }

    /// Where the installers put claude, and node for the npm one: the native installer,
    /// Homebrew, npm's defaults, Volta, Bun, and the newest nvm node.
    private static func searchDirs() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var dirs = ["\(home)/.local/bin", "\(home)/.claude/local", "/opt/homebrew/bin", "/usr/local/bin",
                    "\(home)/.npm-global/bin", "\(home)/.volta/bin", "\(home)/.bun/bin"]
        let nvm = "\(home)/.nvm/versions/node"
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvm) {
            let newest = versions.sorted { $0.compare($1, options: .numeric) == .orderedAscending }.last
            if let newest { dirs.append("\(nvm)/\(newest)/bin") }
        }
        return dirs
    }

    /// Apps don't see the shell's PATH, so look where the installers put it.
    private static func binary() -> URL? {
        searchDirs().map { "\($0)/claude" }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    private static let silent = "no limits reported; is Claude Code signed in to your subscription?"

    /// Looks for the `rate_limit_event` in Claude Code's stream-json output. Its
    /// `unifiedWindows` carry utilization as a fraction and resets as epoch seconds.
    static func parse(_ data: Data) -> Outcome {
        // Each event's windows, merged: a later event updates the windows it carries and keeps the rest,
        // should the windows ever come one per event.
        var reading: ExactReading?
        var error: String?
        for line in data.split(separator: 0x0A) {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else { continue }
            switch obj["type"] as? String {
            case "rate_limit_event":
                guard let info = obj["rate_limit_info"] as? [String: Any],
                      let windows = info["unifiedWindows"] as? [String: Any] else { continue }
                var r = reading ?? ExactReading(at: Date(), source: "probe")
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
            if ["login", "authenticat", "oauth", "expired", "credential", "unauthorized"].contains(where: lower.contains) {
                return .failed(signedOut)
            }
            return .failed(String(error.prefix(80)))
        }
        return .failed(silent)
    }

    /// "seven_day_opus" -> "Weekly · Opus", "five_hour_opus" -> "5-hour · Opus"
    private static func label(_ key: String) -> String {
        func name(_ rest: String) -> String { rest.replacingOccurrences(of: "_", with: " ").capitalized }
        if key.hasPrefix("seven_day_") { return "Weekly · " + name(String(key.dropFirst("seven_day_".count))) }
        if key.hasPrefix("five_hour_") { return "5-hour · " + name(String(key.dropFirst("five_hour_".count))) }
        return name(key)
    }
}
