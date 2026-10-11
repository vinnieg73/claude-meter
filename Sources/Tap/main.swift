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
    // only a newer number is written: a window that climbed, or a later window. Not merely a
    // different one: with two sessions open, an idle one redraws the older numbers it last had,
    // and would flip the file back to them.
    let previous = (try? Data(contentsOf: file))
        .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["rate_limits"] as? [String: Any]
    /// A window's % and reset (epoch seconds; a drop-in may have written milliseconds), if it has both.
    func window(_ block: Any?) -> (pct: Double, resets: Double)? {
        guard let w = block as? [String: Any],
              let pct = (w["used_percentage"] as? NSNumber)?.doubleValue,
              let resets = (w["resets_at"] as? NSNumber)?.doubleValue else { return nil }
        return (pct, resets > 1e11 ? resets / 1000 : resets)
    }
    /// Newer than what the file holds: a later window (resets 15+ minutes after, the meter's
    /// `Window.same`), or the same one higher. A window the file lacks is new too.
    func newer(_ key: String) -> Bool {
        guard let now = window(limits[key]) else { return false }
        guard let held = window(previous?[key]) else { return true }
        if abs(now.resets - held.resets) < 900 { return now.pct > held.pct }
        return now.resets > held.resets
    }
    if limits.keys.contains(where: newer) {
        let record: [String: Any] = ["at": Date().timeIntervalSince1970, "rate_limits": limits]
        if let data = try? JSONSerialization.data(withJSONObject: record) {
            try? data.write(to: file, options: .atomic)
        }
    }
}

// Colour: a percentage turns yellow from 70 and red from 90, the app's warn and critical
// (`WindowView.level` in Meter.swift, which this can't import), judged on the whole percent shown like the
// dropdown does. These are the terminal's own colours, so they suit any theme. Only the foreground
// is set and then reset with 39, never a full reset, so whatever style Claude Code draws the line
// in (dimmed, say) carries on after it. NO_COLOR (no-color.org: set, and not empty) turns it off.
let useColor = (ProcessInfo.processInfo.environment["NO_COLOR"] ?? "").isEmpty

/// "5h 23%", coloured by how high it is.
func segment(_ label: String, _ block: Any?) -> String? {
    // Not a number Int can't hold (a huge or broken value would crash the statusline): clamped.
    guard let used = (block as? [String: Any])?["used_percentage"] as? Double, used.isFinite else { return nil }
    let shown = Int(min(max(used, -9999), 9999).rounded())
    let text = "\(label) \(shown)%"
    // By the whole percent shown, as the app colours, so "70%" is never drawn in the colour of 69.
    guard useColor, shown >= 70 else { return text }
    return "\u{1B}[\(shown >= 90 ? 31 : 33)m\(text)\u{1B}[39m"
}

var parts: [String] = []
if let model = (state["model"] as? [String: Any])?["display_name"] as? String { parts.append(model) }
if let five = segment("5h", limits["five_hour"]) { parts.append(five) }
if let week = segment("7d", limits["seven_day"]) { parts.append(week) }
if let context = segment("ctx", state["context_window"]) { parts.append(context) }
print(parts.joined(separator: " · "))
