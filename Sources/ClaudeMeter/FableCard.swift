import SwiftUI

/// The Fable card: Anthropic's separate weekly limit for Fable (the one limit that is a model's own),
/// as Claude Code's usage report last gave it, over your Fable use (this Mac's, and the cloud sessions'
/// while their list is read) as a part of the overall windows. Gray like the other cards; red takes
/// over near the limit.
struct FableCard: View {
    let f: FableView

    /// Help's symbol for this card (the card itself wears a Fable mascot).
    static let symbol = "sparkles"

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let w = f.limit {
                WindowCard(w: w)
            } else {
                titleRow
                Text(f.noLimit ? "No separate Fable limit on your plan. Fable counts toward the limits above."
                               : "Waiting for a Fable reading.")
                    .font(Theme.row)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let line {
                Text(line)
                    .font(Theme.meta)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .help(tooltip)
            }
        }
    }

    /// The title alone, when there is no limit to put a number on.
    private var titleRow: some View {
        HStack(spacing: 0) {
            MascotTitle(colors: [ModelFamily.fable.full], title: "Fable")
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
        }
        .frame(height: 18)
    }

    /// "This Mac: ~3% of the 5-hour window · ~1% of the week ($2.20)": Fable's part of the overall
    /// windows, from this Mac's logs; "This Mac + cloud: …" with cloud sessions on Fable counted in (1.3,
    /// `FableView.cloud`), shortened to "Mac + cloud" beside a 5-hour part so the line still fits. The
    /// spend alone before the caps are known; "no Fable use this week" when the limit has a number but
    /// nothing counted here added to it.
    var line: String? { // internal for the replay's synthetic checks
        var parts: [String] = []
        if let pts = f.fiveHourPts, (f.fiveHourCost ?? 0) > 0 {
            parts.append("\(Self.points(pts)) of the 5-hour window")
        }
        let who = !f.cloud ? "This Mac" : parts.isEmpty ? "This Mac + cloud" : "Mac + cloud"
        if let cost = f.weekCost {
            if cost > 0 {
                if let pts = f.weekPts {
                    parts.append("\(Self.points(pts)) of the week (\(Fmt.dollars(cost)))")
                } else if f.weekCloud > 0 {
                    parts.append("\(Fmt.dollars(cost)) this week") // the sessions list gives no tokens
                } else {
                    parts.append("\(Fmt.dollars(cost)) · \(Fmt.tokens(f.weekTokens)) tok this week")
                }
            } else if parts.isEmpty {
                return "\(who): no Fable use this week"
            }
        } else if f.todayCost > 0 {
            parts.append("\(Fmt.dollars(f.todayCost)) today")
        }
        guard !parts.isEmpty else { return nil }
        return "\(who): " + parts.joined(separator: " · ")
    }

    /// "~3%", or "<1%" for a sliver, so a little use doesn't read as none.
    private static func points(_ pts: Double) -> String {
        pts < 0.5 ? "<1%" : "~" + Fmt.pct(pts)
    }

    private var tooltip: String {
        var lines = [f.cloud
            ? "Fable's part of your overall limits at pay-as-you-go prices: this Mac's Claude Code logs, and what cloud sessions on Fable cost (Anthropic's sessions list; each part of a session's spend counts under the model it was on when the meter read it)."
            : "Fable's part of your overall limits, estimated from this Mac's Claude Code logs at pay-as-you-go prices."]
        if let c = f.fiveHourCost, c > 0 { lines.append("In the open 5-hour window: \(Fmt.dollars(c)).") }
        if let c = f.weekCost, c > 0 {
            if f.weekCloud > 0 {
                lines.append("This week: \(Fmt.dollars(c)) (\(Fmt.dollars(max(0, c - f.weekCloud))) this Mac, \(Fmt.tokens(f.weekTokens)) tokens; "
                             + "\(Fmt.dollars(f.weekCloud)) cloud sessions); today \(Fmt.dollars(f.todayCost)).")
            } else {
                lines.append("This week: \(Fmt.dollars(c)), \(Fmt.tokens(f.weekTokens)) tokens; today \(Fmt.dollars(f.todayCost)).")
            }
        }
        return lines.joined(separator: "\n")
    }
}
