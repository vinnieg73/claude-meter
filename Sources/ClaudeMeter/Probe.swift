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

    /// What launching claude came to: no CLI, one that wouldn't start, or one that ran (to the end, or
    /// to the minute's limit) and what it wrote.
    private enum Launch {
        case notFound, couldntStart
        case ran(output: Data, errors: Data, timedOut: Bool)
    }

    /// The headless turn: Haiku, no tools, a one-line system prompt, no saved session, none of your settings.
    private static let turnArguments = [
        "-p", "ok", "--model", "haiku",
        "--system-prompt", "Reply with the single word ok.",
        "--tools", "", "--strict-mcp-config", "--no-session-persistence",
        // Your own settings would run your hooks (a "done" sound, say) on every probe.
        "--setting-sources", "", "--settings", #"{"disableAllHooks":true}"#,
        "--output-format", "stream-json", "--verbose",
    ]

    /// Claude Code's usage report (`/usage`): a local command, so no model request, nothing spent and no
    /// window opened. It comes as text inside the one JSON object `--output-format json` prints.
    private static let usageArguments = [
        "-p", "/usage", "--model", "haiku",
        "--tools", "", "--strict-mcp-config", "--no-session-persistence",
        "--setting-sources", "", "--settings", #"{"disableAllHooks":true}"#,
        "--output-format", "json",
    ]

    private static func launch(_ arguments: [String]) -> Launch {
        guard let claude = binary() else { return .notFound }
        // An empty folder, so no CLAUDE.md or project settings load.
        let dir = Paths.support.appendingPathComponent("probe")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = claude
        process.arguments = arguments
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

        do { try process.run() } catch { return .couldntStart }
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

        return .ran(output: output.data, errors: errors.data, timedOut: timedOut)
    }

    private static func runNow() -> Outcome {
        switch launch(turnArguments) {
        case .notFound: return .failed(notFound)
        case .couldntStart: return .failed(couldntStart)
        case .ran(let output, let errors, let timedOut):
            var outcome = parse(output)
            if timedOut, case .failed(let reason) = outcome, reason == Self.silent {
                outcome = .failed(Self.noAnswer)
            }
            // Nothing usable and nothing said why: pass on what claude wrote to stderr.
            if case .failed(let reason) = outcome, reason == Self.silent, let line = lastLine(of: errors) {
                return .failed(line)
            }
            return outcome
        }
    }

    private static let noAnswer = "Claude Code didn't answer within a minute (offline?)"

    /// The last non-blank line claude wrote to stderr, cut to 100 characters.
    private static func lastLine(of errors: Data) -> String? {
        String(decoding: errors, as: UTF8.self).split(separator: "\n")
            .last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
            .map { String($0.prefix(100)) }
    }

    // MARK: Usage report

    /// A limit as the usage report lists it: "Current week (Fable): 7% used · resets Oct 14 at 3pm (America/New_York)".
    struct UsageLimit {
        /// What the line's parentheses hold ("all models", "Fable", "Sonnet only"), or its first word ("session").
        let name: String
        let pct: Double
        /// The reset, when its text could be read; the text as printed either way, so two limits that
        /// reset together can be told to.
        let resetsAt: Date?
        let resetText: String?
    }

    enum UsageOutcome {
        case limits([UsageLimit])
        case failed(String)
    }

    /// The limits Claude Code's own usage report lists. The probe's `rate_limit_event` doesn't carry the
    /// separate weekly Fable limit (it did for a week in September 2026, as `seven_day_fable`); the
    /// report does, as text. A local command: no model request, nothing spent, no window opened.
    static func usage() async -> UsageOutcome {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async { continuation.resume(returning: usageNow()) }
        }
    }

    private static func usageNow() -> UsageOutcome {
        switch launch(usageArguments) {
        case .notFound: return .failed(notFound)
        case .couldntStart: return .failed(couldntStart)
        case .ran(let output, let errors, let timedOut):
            switch parseUsage(output) {
            case .limits(let limits): return .limits(limits)
            case .failed(let reason):
                if timedOut, reason == Self.noReport { return .failed(noAnswer) }
                if reason == Self.noReport, let line = lastLine(of: errors) { return .failed(line) }
                return .failed(reason)
            }
        }
    }

    private static let noReport = "no usage report from Claude Code"

    /// The `result` of the one JSON object `--output-format json` prints, read line by line. A report
    /// with no limit lines at all (an error, a wording change) is a failure, never a plan with no limits.
    static func parseUsage(_ data: Data) -> UsageOutcome {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = obj["result"] as? String else { return .failed(noReport) }
        if obj["is_error"] as? Bool == true {
            let lower = text.lowercased()
            if ["login", "authenticat", "oauth", "expired", "credential", "unauthorized"].contains(where: lower.contains) {
                return .failed(signedOut)
            }
            return .failed(String(text.prefix(80)))
        }
        let limits = parseUsageText(text)
        return limits.isEmpty ? .failed(noReport) : .limits(limits)
    }

    private static let usageLine = try! NSRegularExpression(
        pattern: #"^Current (session|week)(?: \(([^)]+)\))?: (\d+(?:\.\d+)?)% used(?:\s*·\s*resets (.+?))?\s*$"#,
        options: [.anchorsMatchLines])

    /// "Current week (Fable): 7% used · resets Oct 14 at 3pm (America/New_York)", one limit per such line.
    static func parseUsageText(_ text: String, now: Date = Date()) -> [UsageLimit] {
        let whole = NSRange(text.startIndex..., in: text)
        return usageLine.matches(in: text, range: whole).compactMap { m in
            func group(_ i: Int) -> String? {
                guard let r = Range(m.range(at: i), in: text) else { return nil }
                return String(text[r])
            }
            guard let kind = group(1), let pct = group(3).flatMap(Double.init) else { return nil }
            let reset = group(4)
            return UsageLimit(name: group(2) ?? kind, pct: pct,
                              resetsAt: reset.flatMap { parseReset($0, now: now) }, resetText: reset)
        }
    }

    private static let resetText = try! NSRegularExpression(
        pattern: #"^([A-Za-z]{3})[a-z]*\.? (\d{1,2})(?:,? (\d{4}))? at (\d{1,2})(?::(\d{2}))?\s*([AaPp][Mm])?(?:\s*\(([^)]+)\))?"#)
    private static let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]

    /// "Oct 14 at 3pm (America/New_York)" as a moment: that date in that zone (this Mac's zone when none
    /// is given), this year, or next once this year's is well past. Nil for any other wording.
    static func parseReset(_ text: String, now: Date = Date()) -> Date? {
        let whole = NSRange(text.startIndex..., in: text)
        guard let m = resetText.firstMatch(in: text, range: whole) else { return nil }
        func group(_ i: Int) -> String? {
            guard let r = Range(m.range(at: i), in: text) else { return nil }
            return String(text[r])
        }
        guard let month = group(1).flatMap({ months.firstIndex(of: $0.lowercased()) }),
              let day = group(2).flatMap(Int.init), var hour = group(4).flatMap(Int.init) else { return nil }
        let minute = group(5).flatMap(Int.init) ?? 0
        if let ampm = group(6)?.lowercased() {
            guard (1...12).contains(hour) else { return nil }
            hour = hour % 12 + (ampm == "pm" ? 12 : 0)
        }
        guard hour < 24, minute < 60 else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = group(7).flatMap(TimeZone.init(identifier:)) ?? .current
        var parts = DateComponents()
        parts.year = group(3).flatMap(Int.init) ?? cal.component(.year, from: now)
        parts.month = month + 1
        parts.day = day
        parts.hour = hour
        parts.minute = minute
        guard let date = cal.date(from: parts) else { return nil }
        guard group(3) == nil else { return date }
        // No year printed: the year that puts it nearest now (a reset is days away at most; read at the
        // turn of a year, "Dec 31 at 11pm" and "Jan 2 at 3pm" fall either side of it).
        return [-1, 0, 1].compactMap { cal.date(byAdding: .year, value: $0, to: date) }
            .min { abs($0.timeIntervalSince(now)) < abs($1.timeIntervalSince(now)) } ?? date
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
                    // Seconds, as now; milliseconds (as the tap file allows) would put the reset centuries out.
                    let seconds = resets > 1e11 ? resets / 1000 : resets
                    let window = Window(pct: used * 100, resetsAt: Date(timeIntervalSince1970: seconds))
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
