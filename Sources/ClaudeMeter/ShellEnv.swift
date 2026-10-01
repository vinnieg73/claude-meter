import Foundation

/// Variables from your login shell. An app opened from Finder or at login gets launchd's bare
/// environment, not what your shell profile exports.
enum ShellEnv {
    /// Where Claude Code keeps its config, when moved with CLAUDE_CONFIG_DIR. Looked up once.
    static let claudeConfigDir: String? = {
        if let value = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"], !value.isEmpty { return value }
        return fromLoginShell("CLAUDE_CONFIG_DIR")
    }()

    /// Asks an interactive login shell, so both .zprofile and .zshrc are read. A marker sets the
    /// value apart from anything the profile prints, and a shell that hangs is given 3 seconds.
    private static func fromLoginShell(_ name: String) -> String? {
        guard let entry = getpwuid(getuid()), let shellPath = entry.pointee.pw_shell else { return nil }
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
        do { try process.run() } catch { return nil }
        guard exited.wait(timeout: .now() + 3) == .success else {
            process.terminate()
            return nil
        }
        let text = String(decoding: out.fileHandleForReading.availableData, as: UTF8.self)
        guard let range = text.range(of: marker, options: .backwards) else { return nil }
        let value = text[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
