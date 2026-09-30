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
    let file = dir.appendingPathComponent("tap.json")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    // The statusline redraws without a new API call (typing, idle refreshes), carrying the last
    // numbers it had. Stamping those "now" would pass old limits off as a fresh reading, so
    // only a change is written.
    let previous = (try? Data(contentsOf: file))
        .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["rate_limits"] as? NSDictionary
    if previous != (limits as NSDictionary) {
        let record: [String: Any] = ["at": Date().timeIntervalSince1970, "rate_limits": limits]
        if let data = try? JSONSerialization.data(withJSONObject: record) {
            try? data.write(to: file, options: .atomic)
        }
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
