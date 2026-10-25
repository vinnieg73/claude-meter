import Foundation

/// Runs one tiny headless Claude Code turn (Haiku, no tools, a one-line system prompt, no saved
/// session, none of your settings or hooks) and reads the plan limits Claude Code reports
/// alongside it. About $0.001 of usage. Claude Code owns its login; the probe never reads it (only the
/// cloud sessions list does, read only and held in memory: `CloudFeed.swift`).
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
        /// "session" or "week": the line's first word, whatever its parentheses say.
        let kind: String
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
        // Resets printed as a time or a span are read against when the report was asked for, as the meter
        // dates it.
        let asked = Date()
        switch launch(usageArguments) {
        case .notFound: return .failed(notFound)
        case .couldntStart: return .failed(couldntStart)
        case .ran(let output, let errors, let timedOut):
            switch parseUsage(output, now: asked) {
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
    static func parseUsage(_ data: Data, now: Date = Date()) -> UsageOutcome {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = obj["result"] as? String else { return .failed(noReport) }
        if obj["is_error"] as? Bool == true {
            let lower = text.lowercased()
            if ["login", "authenticat", "oauth", "expired", "credential", "unauthorized"].contains(where: lower.contains) {
                return .failed(signedOut)
            }
            return .failed(String(text.prefix(80)))
        }
        let limits = parseUsageText(text, now: now)
        return limits.isEmpty ? .failed(noReport) : .limits(limits)
    }

    private static let usageLine = try! NSRegularExpression(
        pattern: #"^Current (session|week)(?: \(([^)]+)\))?: (\d+(?:\.\d+)?)% used(?:\s*·\s*[Rr]esets (.+?))?\s*$"#,
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
                              resetsAt: reset.flatMap { parseReset($0, now: now) }, resetText: reset, kind: kind)
        }
    }

    /// A clock time and its zone, which ends every dated form below: "3pm", "2:59pm", "10:50 PM", "3 p.m.",
    /// "22:50", then "(America/New_York)" or nothing. Four groups: hour, minute, a or p, zone.
    private static let clockText = #"(\d{1,2})(?::(\d{2}))?\s*(?:([AaPp])\.?[Mm]\.?)?(?![\w:])(?:\s*\(([^)]+)\))?"#
    private static func pattern(_ text: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: text, options: [.caseInsensitive])
    }
    /// "Oct 14 at 3pm", "October 14, 2026 at 3:00 PM", "Oct 14, 3pm": month, day, year, then the clock.
    private static let monthFirst = pattern(#"^([a-z]{3})[a-z]*\.? (\d{1,2})(?:st|nd|rd|th)?(?:,? (\d{4}))?(?:,? at |,? )"# + clockText)
    /// "14 Oct at 3pm", "14 October 2026, 15:00": day, month, year, then the clock.
    private static let dayFirst = pattern(#"^(\d{1,2}) ([a-z]{3})[a-z]*\.?(?:,? (\d{4}))?(?:,? at |,? )"# + clockText)
    /// "in 4 hr 45 min", "in 4h 45m", "in 2 days 3 hours": a span from now.
    private static let span = pattern(#"^in (\d[^(]*)"#)
    private static let spanPart = pattern(#"(\d+)\s*([a-z]+)"#)
    /// "today at 10:50pm", "tomorrow, 9am", "Wed at 3pm", "Wednesday 3pm": a day by name, then the clock.
    private static let namedDay = pattern(#"^([a-z]+)\.?,?(?: at)? "# + clockText)
    /// "10:50pm", "at 3pm", "22:50 (Europe/London)": the clock alone.
    private static let clockOnly = pattern(#"^(?:at )?"# + clockText)
    private static let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
    private static let weekdays = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
    /// A time printed without a date that was this long ago is today's (the report floors to the minute, so
    /// it can be just past), not tomorrow's.
    private static let justPast: TimeInterval = 300

    private struct Clock {
        let hour: Int
        let minute: Int
        let zone: TimeZone
    }

    /// A reset as the usage report prints it, as a moment. With a date ("Oct 14 at 3pm (America/New_York)"):
    /// that date in that zone (this Mac's zone when none is given), this year, or the year either side once
    /// that is nearer. A time alone ("10:50pm (America/New_York)", as the 5-hour line can print it): the next
    /// time the clock reads that, today's unless it is more than a few minutes past. A day by name ("today",
    /// "tomorrow", "Wed"), a span ("in 4 hr 45 min"). Nil for any other wording, which the callers take as
    /// not known.
    static func parseReset(_ text: String, now: Date = Date()) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let whole = NSRange(trimmed.startIndex..., in: trimmed)
        func match(_ form: NSRegularExpression) -> NSTextCheckingResult? { form.firstMatch(in: trimmed, range: whole) }
        if let m = match(monthFirst), let date = dated(m, month: 1, day: 2, in: trimmed, now: now) { return date }
        if let m = match(dayFirst), let date = dated(m, month: 2, day: 1, in: trimmed, now: now) { return date }
        if let m = match(span), let parts = group(m, 1, in: trimmed) { return spanned(parts, now: now) }
        if let m = match(namedDay), let date = onNamedDay(m, in: trimmed, now: now) { return date }
        if let m = match(clockOnly), let time = readClock(m, from: 1, in: trimmed, bare: false) { return next(time, now: now) }
        return nil
    }

    private static func group(_ m: NSTextCheckingResult, _ i: Int, in text: String) -> String? {
        guard i < m.numberOfRanges, let r = Range(m.range(at: i), in: text) else { return nil }
        return String(text[r])
    }

    /// The clock whose four groups start at `first`. Nil for no time of day ("13pm", "24:00"), or for a bare
    /// number unless `bare` (after "Oct 14 at", "15" is 3 PM; alone, "14" is no time).
    private static func readClock(_ m: NSTextCheckingResult, from first: Int, in text: String, bare: Bool) -> Clock? {
        guard var hour = group(m, first, in: text).flatMap({ Int($0) }) else { return nil }
        let minuteText = group(m, first + 1, in: text)
        let ampm = group(m, first + 2, in: text)?.lowercased()
        guard bare || minuteText != nil || ampm != nil else { return nil }
        let minute = minuteText.flatMap { Int($0) } ?? 0
        if let ampm {
            guard (1...12).contains(hour) else { return nil }
            hour = hour % 12 + (ampm == "p" ? 12 : 0)
        }
        guard hour < 24, minute < 60 else { return nil }
        let zone = group(m, first + 3, in: text).flatMap { TimeZone(identifier: $0) ?? TimeZone(abbreviation: $0) }
        return Clock(hour: hour, minute: minute, zone: zone ?? .current)
    }

    /// A printed date and clock (the clock's groups from 4, the year in 3).
    private static func dated(_ m: NSTextCheckingResult, month mi: Int, day di: Int, in text: String, now: Date) -> Date? {
        guard let month = group(m, mi, in: text).flatMap({ months.firstIndex(of: String($0.lowercased().prefix(3))) }),
              let day = group(m, di, in: text).flatMap({ Int($0) }), (1...31).contains(day),
              let time = readClock(m, from: 4, in: text, bare: true) else { return nil }
        let year = group(m, 3, in: text).flatMap { Int($0) }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = time.zone
        var parts = DateComponents()
        parts.year = year ?? cal.component(.year, from: now)
        parts.month = month + 1
        parts.day = day
        parts.hour = time.hour
        parts.minute = time.minute
        guard let date = cal.date(from: parts) else { return nil }
        guard year == nil else { return date }
        // No year printed: the year that puts it nearest now (a reset is days away at most; read at the
        // turn of a year, "Dec 31 at 11pm" and "Jan 2 at 3pm" fall either side of it).
        return [-1, 0, 1].compactMap { cal.date(byAdding: .year, value: $0, to: date) }
            .min { abs($0.timeIntervalSince(now)) < abs($1.timeIntervalSince(now)) } ?? date
    }

    /// "4 hr 45 min" from now. Nil when any part's unit isn't a day, hour, minute or second, or none is there.
    private static func spanned(_ parts: String, now: Date) -> Date? {
        let found = spanPart.matches(in: parts, range: NSRange(parts.startIndex..., in: parts))
        guard !found.isEmpty else { return nil }
        var seconds: TimeInterval = 0
        for m in found {
            guard let n = group(m, 1, in: parts).flatMap({ Double($0) }), let unit = group(m, 2, in: parts)?.lowercased() else { return nil }
            if unit.hasPrefix("w") { seconds += n * 7 * 86400 }
            else if unit.hasPrefix("d") { seconds += n * 86400 }
            else if unit.hasPrefix("h") { seconds += n * 3600 }
            else if unit.hasPrefix("mo") { return nil } // months: no reset is that far
            else if unit.hasPrefix("m") { seconds += n * 60 }
            else if unit.hasPrefix("s") { seconds += n }
            else { return nil }
        }
        return now.addingTimeInterval(seconds)
    }

    /// "today at 10:50pm", "tomorrow, 9am", "Wed at 3pm": that day's time; a weekday is its next one (today's
    /// unless that time is more than a few minutes past).
    private static func onNamedDay(_ m: NSTextCheckingResult, in text: String, now: Date) -> Date? {
        guard let word = group(m, 1, in: text)?.lowercased(), let time = readClock(m, from: 2, in: text, bare: false) else { return nil }
        switch word {
        case "today", "tonight": return on(time, daysAfter: 0, now: now)
        case "tomorrow": return on(time, daysAfter: 1, now: now)
        default:
            guard word.count >= 3, let weekday = weekdays.firstIndex(where: { $0.hasPrefix(word) }) else { return nil }
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = time.zone
            return next(time, now: now) { cal.component(.weekday, from: $0) == weekday + 1 }
        }
    }

    /// The clock's time on the day `days` after today, both in the clock's zone.
    private static func on(_ clock: Clock, daysAfter days: Int, now: Date) -> Date? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = clock.zone
        guard let day = cal.date(byAdding: .day, value: days, to: cal.startOfDay(for: now)) else { return nil }
        return cal.date(bySettingHour: clock.hour, minute: clock.minute, second: 0, of: day)
    }

    /// The next time the clock reads `clock` on a day that `fits`, up to a week on; one a few minutes past
    /// (yesterday's, just after midnight) is that one, not the next.
    private static func next(_ clock: Clock, now: Date, fits: (Date) -> Bool = { _ in true }) -> Date? {
        for days in -1...7 {
            guard let date = on(clock, daysAfter: days, now: now) else { return nil }
            if date >= now.addingTimeInterval(-justPast), fits(date) { return date }
        }
        return nil
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
