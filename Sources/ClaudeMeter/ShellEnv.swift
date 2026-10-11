import Foundation

/// Variables from your login shell. An app opened from Finder or at login gets launchd's bare
/// environment, not what your shell profile exports.
enum ShellEnv {
    /// Where Claude Code keeps its config, when moved with CLAUDE_CONFIG_DIR. Looked up until the
    /// shell answers: a profile slow enough to time out once is asked again next time, up to three
    /// times, then taken as unset (a shell that never answers would otherwise stall every lookup).
    /// Blocks while it asks, so it is read off the main thread.
    static var claudeConfigDir: String? {
        lock.lock()
        defer { lock.unlock() }
        if let answer { return answer }
        if let value = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"], !value.isEmpty {
            answer = .some(value)
            return value
        }
        guard let value = fromLoginShell("CLAUDE_CONFIG_DIR") else {
            timeouts += 1
            if timeouts >= 3 { answer = .some(nil) }
            return nil
        }
        answer = .some(value)
        return value
    }

    /// Whether `claudeConfigDir` has its final answer (set or not), rather than a timed-out guess.
    static var settled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return answer != nil
    }

    private static let lock = NSLock()
    /// Nil until the shell answers; then the value, which may itself be nil (unset).
    nonisolated(unsafe) private static var answer: String??
    nonisolated(unsafe) private static var timeouts = 0

    /// Asks an interactive login shell, so both .zprofile and .zshrc are read. A marker sets the
    /// value apart from anything the profile prints. Nil when the shell didn't answer within 10
    /// seconds (or couldn't run); `.some(nil)` when it answered and the variable is unset.
    private static func fromLoginShell(_ name: String) -> String?? {
        guard let entry = getpwuid(getuid()), let shellPath = entry.pointee.pw_shell else { return .some(nil) }
        let marker = "__CLAUDE_METER__"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: String(cString: shellPath))
        process.arguments = ["-lic", "printf '\\n\(marker)%s' \"$\(name)\""]
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let out = Pipe()
        process.standardOutput = out
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        // Drained as it runs: a profile that prints more than a pipe holds would otherwise block on
        // the full pipe until the timeout. Never waited to the end, though: something the profile left
        // running in the background can hold the pipe open long after the shell has exited.
        let lock = NSLock()
        nonisolated(unsafe) var output = Data()
        out.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty { handle.readabilityHandler = nil; return }
            lock.lock(); output.append(chunk); lock.unlock()
        }
        defer { out.fileHandleForReading.readabilityHandler = nil }
        do { try process.run() } catch { return nil } // asked again, up to three times, not taken as unset
        guard exited.wait(timeout: .now() + 10) == .success else {
            process.terminate()
            // Not every shell gives way to SIGTERM (an interactive bash ignores it).
            if exited.wait(timeout: .now() + 2) == .timedOut { kill(process.processIdentifier, SIGKILL) }
            return nil
        }
        // What it printed before exiting may still be on its way through the pipe.
        Thread.sleep(forTimeInterval: 0.2)
        lock.lock(); let text = String(decoding: output, as: UTF8.self); lock.unlock()
        // No marker: the profile exited before the command ran. Not an answer; asked again.
        guard let range = text.range(of: marker, options: .backwards) else { return nil }
        let value = text[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        return .some(value.isEmpty ? nil : value)
    }
}
