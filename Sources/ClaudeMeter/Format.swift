import AppKit
import Foundation

enum Fmt {
    /// Each unit up to where its rounding would show 1000 of it ("$1000", "1000k"), the next one from there.
    static func dollars(_ v: Double) -> String {
        if v == 0 { return "$0" }
        if v >= 999_950 { return String(format: "$%.1fM", v / 1e6) }
        if v >= 999.5 { return String(format: "$%.1fk", v / 1000) }
        if v >= 99.995 { return String(format: "$%.0f", v) }
        return String(format: "$%.2f", v)
    }

    static func tokens(_ n: Int) -> String {
        let v = Double(n)
        if v >= 999_500_000 { return String(format: "%.1fB", v / 1e9) }
        if v >= 99_950_000 { return String(format: "%.0fM", v / 1e6) }
        if v >= 999_500 { return String(format: "%.1fM", v / 1e6) }
        if v >= 1e3 { return String(format: "%.0fk", v / 1e3) }
        return "\(n)"
    }

    /// Time left: a duration, or "<1m" in the last minute rather than "0m" with seconds still to go.
    static func left(_ seconds: TimeInterval) -> String { seconds < 60 ? "<1m" : duration(seconds) }

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

    /// Localized templates, so a 24-hour clock setting is honoured, and time zone and locale
    /// that follow the system: the app runs for days, across trips and DST.
    private static func formatter(_ template: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = .autoupdatingCurrent
        f.timeZone = .autoupdatingCurrent
        f.setLocalizedDateFormatFromTemplate(template)
        return f
    }
    private static let time = formatter("jmm")
    private static let dayTime = formatter("EEEjmm")
    private static let dateTime = formatter("MMMdjmm")

    private static let weekday = formatter("EEE")

    /// The time of day with AM or PM ("10:49 AM"), for the title's run-out time (asked for 2026-11-04: a bare
    /// "10:49" doesn't say which). A 24-hour clock has no period and reads as before.
    static func periodClock(_ date: Date) -> String {
        time.string(from: Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 60).rounded() * 60))
    }
    /// "Sun 9:40 AM": the same with its weekday, for a run-out that isn't today.
    static func periodDayClock(_ date: Date) -> String { weekday.string(from: date) + " " + periodClock(date) }

    /// The widest the menu bar title's text can be: 178.5 pt right of the notch beside the 58 pt Vitals dials,
    /// less the ring and its gaps (38.5 pt), measured with the real font and formatter.
    static let titleTextBudget = 140.0
    private static let titleFont = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    static func titleWidth(_ text: String) -> Double {
        Double(NSAttributedString(string: text, attributes: [.font: titleFont]).size().width)
    }
    /// The first of `candidates` (longest first) that fits beside the notch; the last if none does.
    static func fittingTitle(_ candidates: [String]) -> String {
        candidates.first { titleWidth($0) <= titleTextBudget } ?? candidates.last ?? ""
    }

    /// "3:50 PM" today, "Wed 3:50 PM" within six days, "Sep 30, 3:50 PM" beyond.
    static func when(_ date: Date) -> String {
        // The API reports resets like 18:59:59.5; show the minute it means.
        let date = Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 60).rounded() * 60)
        if Calendar.current.isDateInToday(date) { return time.string(from: date) }
        if abs(date.timeIntervalSinceNow) < 6 * 86400 { return dayTime.string(from: date) }
        return dateTime.string(from: date)
    }

    static func ago(_ date: Date) -> String {
        let s = Date().timeIntervalSince(date)
        if s < 90 { return "just now" }
        return duration(s) + " ago"
    }

    /// "claude-opus-5-5" -> "Opus 5.5", "claude-haiku-4-5-20251001" -> "Haiku 4.5",
    /// and the older order "claude-3-5-sonnet-20241022" -> "Sonnet 3.5"
    static func model(_ id: String) -> String {
        // "[1m]" and similar mark a variant, not a version.
        // A vendor's prefix ("us.anthropic.") isn't part of the name.
        let base = Pricing.bare(id).split(separator: "[").first.map(String.init) ?? id
        var parts = base.split(separator: "-").map(String.init)
        if parts.first == "claude" { parts.removeFirst() }
        func isVersion(_ s: String) -> Bool { s.count <= 2 && Int(s) != nil }
        guard let at = parts.firstIndex(where: { !isVersion($0) }) else { return id }
        var version = parts[(at + 1)...].prefix(while: isVersion)
        if version.isEmpty { version = ArraySlice(parts[..<at].filter(isVersion)) }
        let name = parts[at].capitalized
        return version.isEmpty ? name : "\(name) \(version.joined(separator: "."))"
    }
}
