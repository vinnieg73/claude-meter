import Foundation

enum Fmt {
    static func dollars(_ v: Double) -> String {
        if v == 0 { return "$0" }
        if v >= 1000 { return String(format: "$%.1fk", v / 1000) }
        if v >= 100 { return String(format: "$%.0f", v) }
        return String(format: "$%.2f", v)
    }

    static func tokens(_ n: Int) -> String {
        let v = Double(n)
        if v >= 1e9 { return String(format: "%.1fB", v / 1e9) }
        if v >= 1e8 { return String(format: "%.0fM", v / 1e6) }
        if v >= 1e6 { return String(format: "%.1fM", v / 1e6) }
        if v >= 1e3 { return String(format: "%.0fk", v / 1e3) }
        return "\(n)"
    }

    static func pct(_ v: Double) -> String { "\(Int(v.rounded()))%" }

    /// A rate: one decimal while it is small enough for the decimal to matter.
    static func rate(_ v: Double) -> String { String(format: v < 10 ? "%.1f" : "%.0f", v) }

    /// "32m", "3h10m", "5d 20h"
    static func duration(_ seconds: TimeInterval) -> String {
        let m = Int(max(0, seconds) / 60)
        if m < 60 { return "\(m)m" }
        if m < 1440 { return String(format: "%dh%02dm", m / 60, m % 60) }
        return "\(m / 1440)d \(m % 1440 / 60)h"
    }

    /// "3:50 PM" today, "Wed 3:50 PM" this week, "Sep 30" beyond.
    static func when(_ date: Date) -> String {
        // The API reports resets like 18:59:59.5; show the minute it means.
        let date = Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 60).rounded() * 60)
        let f = DateFormatter()
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            f.dateFormat = "h:mm a"
        } else if abs(date.timeIntervalSinceNow) < 6 * 86400 {
            f.dateFormat = "EEE h:mm a"
        } else {
            f.dateFormat = "MMM d"
        }
        return f.string(from: date)
    }

    static func ago(_ date: Date) -> String {
        let s = Date().timeIntervalSince(date)
        if s < 90 { return "just now" }
        return duration(s) + " ago"
    }

    /// "claude-opus-5-5" -> "Opus 5.5", "claude-haiku-4-5-20251001" -> "Haiku 4.5"
    static func model(_ id: String) -> String {
        var parts = id.split(separator: "-").map(String.init)
        if parts.first == "claude" { parts.removeFirst() }
        guard let family = parts.first else { return id }
        let version = parts.dropFirst().prefix { $0.count <= 2 && Int($0) != nil }
        return ([family.capitalized] + (version.isEmpty ? [] : [version.joined(separator: ".")]))
            .joined(separator: " ")
    }
}
