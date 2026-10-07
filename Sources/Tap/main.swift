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

// Colour: a percentage turns yellow from 70 and red from 90, the app's warn and critical
// (`WindowView.level` in Meter.swift, which this can't import), judged on the exact number like the
// dropdown does. These are the terminal's own colours, so they suit any theme. Only the foreground
// is set and then reset with 39, never a full reset, so whatever style Claude Code draws the line
// in (dimmed, say) carries on after it. NO_COLOR (no-color.org: set, and not empty) turns it off.
let useColor = (ProcessInfo.processInfo.environment["NO_COLOR"] ?? "").isEmpty

/// "5h 23%", coloured by how high it is.
func segment(_ label: String, _ block: Any?) -> String? {
    guard let used = (block as? [String: Any])?["used_percentage"] as? Double else { return nil }
    let text = "\(label) \(Int(used.rounded()))%"
    guard useColor, used >= 70 else { return text }
    return "\u{1B}[\(used >= 90 ? 31 : 33)m\(text)\u{1B}[39m"
}

var parts: [String] = []
if let model = (state["model"] as? [String: Any])?["display_name"] as? String { parts.append(model) }
if let five = segment("5h", limits["five_hour"]) { parts.append(five) }
if let week = segment("7d", limits["seven_day"]) { parts.append(week) }
if let context = segment("ctx", state["context_window"]) { parts.append(context) }
print(parts.joined(separator: " · "))
