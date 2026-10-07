import Charts
import SwiftUI

/// Today's spend by project, or each project's share of the weekly limit, and the last 7 days.
struct UsageSection: View {
    let s: Snapshot
    @AppStorage("weekScope") private var weekScope = false

    var body: some View {
        let week = weekScope && !s.weekShares.isEmpty
        VStack(alignment: .leading, spacing: 5) {
            header(week: week)

            // Left out when there is nothing to list (a fresh day), so the empty stack doesn't
            // leave a double gap between the header and the chart.
            if week || !s.projects.isEmpty {
                VStack(spacing: 1) {
                    if week { weekRows } else { todayRows }
                }
            }

            if s.models.count > 1 {
                Text(s.models.prefix(3).map { "\($0.id) \(Fmt.dollars($0.cost))" }.joined(separator: " · "))
                    .font(Theme.meta).monospacedDigit().foregroundStyle(.secondary).lineLimit(1)
            }

            DailyChart(daily: s.daily)
        }
    }

    // MARK: Header

    /// The Today / This week picker (or just "Today" while there is no weekly split), and the
    /// summary on the right, on the picker's baseline.
    private func header(week: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if s.weekShares.isEmpty {
                ModuleTitle(symbol: "sun.max", title: "Today")
            } else {
                Picker("Time range", selection: $weekScope) {
                    Text("Today").tag(false)
                    Text("This week").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
            }
            Spacer(minLength: 6)
            summary(week: week)
                .font(Theme.meta).monospacedDigit().foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.85)
        }
    }

    @ViewBuilder
    private func summary(week: Bool) -> some View {
        if week {
            let logged = s.weekShares.reduce(0) { $0 + $1.pct }
            Text("\(Fmt.pct(logged)) of weekly limit from this Mac")
        } else {
            let hit = s.cacheHit.map { " · cache \(Fmt.pct($0 * 100))" } ?? ""
            Text("\(Fmt.dollars(s.todayCost)) · \(Fmt.tokens(s.todayTokens)) tok\(hit)")
                .help("API-list-price equivalent of today's Claude Code usage on this Mac.")
        }
    }

    // MARK: Rows

    /// Each project's share of today, drawn behind its row.
    @ViewBuilder
    private var todayRows: some View {
        let top = max(s.projects.first?.cost ?? 1, 0.01)
        ForEach(s.projects.prefix(4)) { row in
            BarRow(name: row.id, value: Fmt.dollars(row.cost), fraction: row.cost / top)
                .accessibilityElement(children: .combine)
        }
    }

    /// Each project as a share of the weekly limit (its spend alongside), and what the logs can't
    /// account for.
    @ViewBuilder
    private var weekRows: some View {
        let top = max(s.weekShares.first?.pct ?? 1, 0.01)
        ForEach(s.weekShares.prefix(4)) { share in
            BarRow(name: share.id, value: Fmt.pct(share.pct), detail: Fmt.dollars(share.cost),
                   fraction: share.pct / top)
                .accessibilityElement(children: .combine)
        }
        if let elsewhere = s.weekElsewhere {
            // No bar, set apart, and quieter than the projects: this part isn't from this Mac. The
            // empty detail keeps its % in the projects' column.
            BarRow(name: "Elsewhere (chat, other devices)", value: Fmt.pct(elsewhere), detail: "", fraction: 0)
                .foregroundStyle(.secondary)
                .padding(.top, 3)
                .accessibilityElement(children: .combine)
        }
    }
}

/// Spend per day for the last 7 days, today highlighted.
struct DailyChart: View {
    let daily: [DayBar]

    private static let axisFont = Font.system(size: 9)

    var body: some View {
        let tallest = daily.map(\.cost).max() ?? 0
        let top = Self.scaleTop(for: tallest)
        Chart(daily) { bar in
            let isToday = Calendar.current.isDateInToday(bar.day)
            BarMark(x: .value("Day", bar.day, unit: .day), y: .value("Cost", bar.cost), width: .ratio(0.6))
                // Rounded at the top only: the bottom sits on the baseline.
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3, style: .continuous))
                .foregroundStyle(isToday ? Color.accentColor : Theme.quiet)
                // The accent says "today" to the eye; say it to VoiceOver too.
                .accessibilityLabel(isToday ? "Today" : bar.day.formatted(.dateTime.weekday(.wide)))
                .accessibilityValue(Fmt.dollars(bar.cost))
        }
        .chartYScale(domain: 0...top)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                // Centered in the day's slot, which is where its bar is.
                AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                    .font(Self.axisFont)
                    .foregroundStyle(Color.secondary)
            }
        }
        .chartYAxis {
            // Gridlines at the bottom, middle and top; only the top says what it is.
            AxisMarks(position: .trailing, values: [0, top / 2, top]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Theme.track)
                if tallest > 0, value.as(Double.self) == top {
                    AxisValueLabel { Text(Self.label(top)).monospacedDigit() }
                        .font(Self.axisFont)
                        .foregroundStyle(Color.secondary)
                }
            }
        }
        .frame(height: 40)
        .padding(.top, 4)
        .accessibilityLabel("Spend per day, last 7 days")
    }

    /// The first round figure (1, 1.5, 2, 2.5, 3, 4, 5, 6 or 8 times a power of ten) at or above
    /// the tallest day, so the top gridline reads cleanly and the bars still fill most of the plot.
    private static func scaleTop(for tallest: Double) -> Double {
        let tallest = max(tallest, 0.01)
        let magnitude = pow(10, floor(log10(tallest)))
        let steps: [Double] = [1, 1.5, 2, 2.5, 3, 4, 5, 6, 8, 10]
        return (steps.first { $0 * magnitude >= tallest * 0.9999 } ?? 10) * magnitude
    }

    /// "$400", "$15k", "$0.50": a dollar figure without the cents or ".0" it would carry in the list.
    private static func label(_ value: Double) -> String {
        if value >= 1000 { return String(format: "$%gk", value / 1000) }
        return value == value.rounded() ? "$\(Int(value))" : Fmt.dollars(value)
    }
}
