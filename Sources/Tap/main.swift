import Foundation

// Claude Code statusline command. Claude Code pipes the session's state in on stdin,
// including the exact plan limits it read from the API; this saves that block for
// ClaudeMeter and prints a short status line back.

let input = FileHandle.standardInput.readDataToEndOfFile()
guard let state = try? JSONSerialization.jsonObject(with: input) as? [String: Any] else { exit(0) }

let limits = state["rate_limits"] as? [String: Any] ?? [:]
if !limits.isEmpty {
    let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("ClaudeMeter")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let record: [String: Any] = ["at": Date().timeIntervalSince1970, "rate_limits": limits]
    if let data = try? JSONSerialization.data(withJSONObject: record) {
        try? data.write(to: dir.appendingPathComponent("tap.json"), options: .atomic)
    }
}

func pct(_ block: Any?) -> String? {
    guard let used = (block as? [String: Any])?["used_percentage"] as? Double else { return nil }
    return "\(Int(used.rounded()))%"
}

var parts: [String] = []
if let model = (state["model"] as? [String: Any])?["display_name"] as? String { parts.append(model) }
if let five = pct(limits["five_hour"]) { parts.append("5h \(five)") }
if let week = pct(limits["seven_day"]) { parts.append("7d \(week)") }
if let context = pct(state["context_window"]) { parts.append("ctx \(context)") }
print(parts.joined(separator: " · "))
