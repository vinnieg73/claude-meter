import SwiftUI

/// History's "Value this week": the week so far at pay-as-you-go prices, as a multiple of what the
/// plan costs for a week, then each day and each model. Grayscale (this Mac, the cloud and Other are
/// three grays); only the plan's tick is coloured.
struct WeekValueSection: View {
    let h: History
    let plan: Plan

    static let symbol = "dollarsign.circle"
    /// This Mac's part, the cloud sessions', Other (the estimate), and the plan's week.
    static let macColor = Color.primary.opacity(0.72)
    static let cloudColor = Color.primary.opacity(0.42)
    static let elsewhereColor = Color.primary.opacity(0.2)
    static let planColor = Color.blue

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                ModuleTitle(symbol: Self.symbol, title: "Value this week")
                Spacer(minLength: 0)
                if let v = h.value {
                    Text("since \(Fmt.when(v.begin)) · resets \(Fmt.when(v.resets))")
                        .font(Theme.meta).monospacedDigit().foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            if let v = h.value {
                hero(v)
                ValueBar(v: v, plan: plan)
                legend(v)
                if let apps = h.surfaces {
                    Text("Anthropic's split of the week by app: " + PlanCredits.surfaceText(apps, short: false))
                        .font(Theme.meta).monospacedDigit().foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ValueDays(days: v.days)
                    .padding(.top, 2)
                if !v.models.isEmpty { models(v) }
            } else {
                noReading
            }
        }
    }

    // MARK: - Hero

    private func hero(_ v: WeekValue) -> some View {
        let estimated = v.elsewhere != nil
        return HStack(alignment: .lastTextBaseline, spacing: 22) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    if estimated { Text("~").font(Self.unit).opacity(0.65) }
                    Text(Fmt.dollars(v.total)).font(Self.big)
                }
                Text("at pay-as-you-go prices").font(Theme.meta).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Worth \(estimated ? "about " : "")\(Fmt.dollars(v.total)) at pay-as-you-go prices")
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(Self.multiple(v.total, plan)).font(Self.mid)
                    Text("×").font(Self.unit)
                }
                Text("what \(plan.name) costs for a week (\(Self.price(plan.weeklyPrice)))")
                    .font(Theme.meta).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(Self.multiple(v.total, plan)) times what \(plan.name) costs for a week, \(Self.price(plan.weeklyPrice))")
            Spacer(minLength: 0)
        }
        .lineLimit(1)
    }

    private static let big = Font.system(size: 28, weight: .semibold, design: .rounded).monospacedDigit()
    private static let mid = Font.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit()
    private static let unit = Font.system(size: 15, weight: .semibold, design: .rounded)

    /// "11.7", or "268" once the decimal stops mattering.
    static func multiple(_ total: Double, _ plan: Plan) -> String {
        let x = total / plan.weeklyPrice
        return String(format: x < 100 ? "%.1f" : "%.0f", x)
    }

    /// A plan's price in whole dollars ("$46"), with cents only under $10 ("$4.62").
    static func price(_ v: Double) -> String { v >= 10 ? "$\(Int(v.rounded()))" : Fmt.dollars(v) }

    // MARK: - Legend and models

    /// Four entries can outgrow the line; then the shorter names.
    private func legend(_ v: WeekValue) -> some View {
        ViewThatFits(in: .horizontal) {
            legendLine(v, short: false)
            legendLine(v, short: true)
        }
        .font(Theme.meta).monospacedDigit().foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private func legendLine(_ v: WeekValue, short: Bool) -> some View {
        HStack(spacing: short ? 10 : 14) {
            Swatch(color: Self.macColor, text: (short ? "This Mac " : "This Mac's Claude Code ") + Fmt.dollars(v.mac))
            if let c = v.cloud, c > 0 {
                Swatch(color: Self.cloudColor, text: (short ? "Cloud " : "Cloud sessions ") + Fmt.dollars(c))
            }
            if let e = v.elsewhere {
                Swatch(color: Self.elsewhereColor, text: "Other ~\(Fmt.dollars(e))")
            }
            Swatch(color: Self.planColor, text: (short ? "Plan's week " : "Your plan's week ") + Self.price(plan.weeklyPrice))
        }
        .fixedSize()
    }

    private func models(_ v: WeekValue) -> some View {
        var text = AttributedString("By model on this Mac: ")
        for (i, m) in v.models.prefix(4).enumerated() {
            if i > 0 { text += AttributedString(" · ") }
            var name = AttributedString(m.id)
            name.foregroundColor = .primary
            name.font = Font.system(size: 11, weight: .medium)
            text += name + AttributedString(" \(Fmt.dollars(m.cost))")
        }
        return Text(text)
            .font(Theme.row).monospacedDigit().foregroundStyle(.secondary)
            .lineLimit(1).truncationMode(.tail)
    }

    // MARK: - No reading

    private var noReading: some View {
        HStack(spacing: 5) {
            Image(systemName: Self.symbol)
                .font(.system(size: 10, weight: .semibold))
                .accessibilityHidden(true)
            Text("No weekly reading yet.")
        }
        .font(Theme.row)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, minHeight: 36)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.surface))
    }
}

/// A legend entry: a small square in the colour it names.
private struct Swatch: View {
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2, style: .continuous).fill(color)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(text)
        }
    }
}

// MARK: - Bar

/// This Mac, then the cloud sessions, then Other, on one track, with the plan's week as a tick. Scaled
/// to whichever is longer, so a light week's tick still lands on the track.
private struct ValueBar: View {
    let v: WeekValue
    let plan: Plan

    private static let height: CGFloat = 10

    var body: some View {
        let scale = max(v.total, plan.weeklyPrice, 0.01)
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    Rectangle().fill(WeekValueSection.macColor).frame(width: w * v.mac / scale)
                    Rectangle().fill(WeekValueSection.cloudColor).frame(width: w * (v.cloud ?? 0) / scale)
                    Rectangle().fill(WeekValueSection.elsewhereColor).frame(width: w * (v.elsewhere ?? 0) / scale)
                    Spacer(minLength: 0)
                }
                .background(Theme.track)
                .clipShape(Capsule())
                Rectangle().fill(WeekValueSection.planColor)
                    .frame(width: 2, height: Self.height + 4)
                    .offset(x: min(max(w * plan.weeklyPrice / scale - 1, 0), w - 2))
            }
        }
        .frame(height: Self.height + 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("This week's value against the plan")
        .accessibilityValue(spoken)
    }

    private var spoken: String {
        var parts = ["This Mac \(Fmt.dollars(v.mac))"]
        if let c = v.cloud, c > 0 { parts.append("cloud sessions \(Fmt.dollars(c))") }
        if let e = v.elsewhere { parts.append("other about \(Fmt.dollars(e))") }
        parts.append("your plan's week \(WeekValueSection.price(plan.weeklyPrice))")
        return parts.joined(separator: ", ")
    }
}

// MARK: - Days

/// A column per local day: this Mac's and the cloud's amount over its bar, the cloud stacked on this
/// Mac (Other can't be split by day). Days still to come are stubs; today's label is bold.
private struct ValueDays: View {
    let days: [ValueDay]

    private static let tallest: CGFloat = 56
    private static let amount = Font.system(size: 9.5)

    var body: some View {
        let top = max(days.map { $0.mac + $0.cloud }.max() ?? 0, 0.01)
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(days) { d in column(d, top: top) }
        }
    }

    private func column(_ d: ValueDay, top: Double) -> some View {
        let today = Calendar.current.isDateInToday(d.day)
        let empty = d.future || d.before
        let total = d.mac + d.cloud
        return VStack(spacing: 3) {
            Text(empty ? " " : Self.short(total))
                .font(Self.amount).monospacedDigit().foregroundStyle(.secondary)
                .lineLimit(1).fixedSize()
            Group {
                if empty || total <= 0 {
                    Rectangle().fill(Theme.track).frame(height: 3)
                } else {
                    VStack(spacing: 0) {
                        if d.cloud > 0 {
                            Rectangle().fill(WeekValueSection.cloudColor).frame(height: max(1, Self.tallest * d.cloud / top))
                        }
                        if d.mac > 0 {
                            Rectangle().fill(WeekValueSection.macColor).frame(height: max(1, Self.tallest * d.mac / top))
                        }
                    }
                }
            }
            .frame(maxWidth: 34)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3, style: .continuous))
            Text(d.day.formatted(.dateTime.weekday(.abbreviated)))
                .font(.system(size: 10, weight: today ? .semibold : .regular))
                .foregroundStyle(today ? Color.primary : d.future ? Color.secondary.opacity(0.6) : Color.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(today ? "Today" : d.day.formatted(.dateTime.weekday(.wide)))
        .accessibilityValue(empty ? "nothing yet" : spoken(d))
    }

    private func spoken(_ d: ValueDay) -> String {
        d.cloud > 0 ? "\(Fmt.dollars(d.mac + d.cloud)), cloud sessions \(Fmt.dollars(d.cloud))" : Fmt.dollars(d.mac)
    }

    /// Whole dollars from $10 up, so eight columns stay short ("$112", "$4.20").
    private static func short(_ v: Double) -> String {
        v >= 10 && v < 999.5 ? "$\(Int(v.rounded()))" : Fmt.dollars(v)
    }
}

// MARK: - Dropdown line

/// Under the weekly card: the week's value and the multiple of the plan, with a way into History.
struct WeekValueLine: View {
    let v: WeekValue
    let plan: Plan
    var openHistory: () -> Void = {}

    var body: some View {
        let worth = (v.elsewhere != nil ? "~" : "") + Fmt.dollars(v.total)
        let times = WeekValueSection.multiple(v.total, plan) + "×"
        let w = Text(worth).fontWeight(.medium).foregroundColor(.primary)
        let x = Text(times).fontWeight(.medium).foregroundColor(.primary)
        HStack(spacing: 6) {
            ViewThatFits(in: .horizontal) {
                Text("Worth ") + w + Text(" so far · ") + x + Text(" your plan")
                w + Text(" · ") + x + Text(" your plan")
            }
            .lineLimit(1)
            .accessibilityLabel("Worth \(worth.replacingOccurrences(of: "~", with: "about ")) so far, \(times) your plan")
            Spacer(minLength: 4)
            Button { openHistory() } label: {
                HStack(spacing: 2) {
                    Text("History")
                    Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .fixedSize()
            .accessibilityLabel("Open History")
        }
        .font(Theme.row)
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .padding(.top, 5)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 0.5) }
    }
}
