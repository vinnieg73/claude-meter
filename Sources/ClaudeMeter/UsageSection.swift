import Charts
import SwiftUI

/// Today's spend by project, or each project's share of the weekly limit, and the last 7 days.
struct UsageSection: View {
    let s: Snapshot
    @AppStorage("weekScope") private var weekScope = false

    var body: some View {
        let week = weekScope && !s.weekShares.isEmpty
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center) {
                if s.weekShares.isEmpty {
                    Text("Today").font(.subheadline.weight(.semibold))
                } else {
                    Picker("", selection: $weekScope) {
                        Text("Today").tag(false)
                        Text("This week").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.small)
                    .fixedSize()
                }
                Spacer()
                if week {
                    let logged = s.weekShares.reduce(0) { $0 + $1.pct }
                    Text("\(Fmt.pct(logged)) of weekly limit from this Mac")
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                } else {
                    let hit = s.cacheHit.map { " · cache \(Fmt.pct($0 * 100))" } ?? ""
                    Text("\(Fmt.dollars(s.todayCost)) · \(Fmt.tokens(s.todayTokens)) tok\(hit)")
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        .help("API-list-price equivalent of today's Claude Code usage on this Mac.")
                }
            }

            if week {
                // Each project as a share of the weekly limit.
                let top = max(s.weekShares.first?.pct ?? 1, 0.01)
                ForEach(s.weekShares.prefix(4)) { share in
                    barRow(share.id, value: "\(Fmt.pct(share.pct)) · \(Fmt.dollars(share.cost))",
                           fraction: share.pct / top)
                }
                if let elsewhere = s.weekElsewhere {
                    barRow("Elsewhere (chat, other devices)", value: Fmt.pct(elsewhere), fraction: 0)
                        .foregroundStyle(.secondary)
                }
            } else {
                // Each project's share of today, drawn behind its row.
                let top = max(s.projects.first?.cost ?? 1, 0.01)
                ForEach(s.projects.prefix(4)) { row in
                    barRow(row.id, value: Fmt.dollars(row.cost), fraction: row.cost / top)
                }
            }

            if s.models.count > 1 {
                Text(s.models.prefix(3).map { "\($0.id) \(Fmt.dollars($0.cost))" }.joined(separator: " · "))
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }

            DailyChart(daily: s.daily)
                .padding(.top, 4)
        }
    }

    private func barRow(_ name: String, value: String, fraction: Double) -> some View {
        HStack {
            Text(name).lineLimit(1)
            Spacer()
            Text(value).monospacedDigit().foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(alignment: .leading) {
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.accentColor.opacity(fraction > 0 ? 0.22 : 0))
                    .frame(width: max(3, geo.size.width * min(fraction, 1)))
            }
        }
    }
}

/// Spend per day for the last 7 days, today highlighted.
struct DailyChart: View {
    let daily: [DayBar]

    var body: some View {
        Chart(daily) { bar in
            BarMark(x: .value("Day", bar.day, unit: .day), y: .value("Cost", bar.cost))
                .foregroundStyle(Calendar.current.isDateInToday(bar.day)
                                 ? Color.accentColor : Color.secondary.opacity(0.45))
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisValueLabel(format: .dateTime.weekday(.narrow))
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 2)) { value in
                AxisGridLine()
                AxisValueLabel { Text(Fmt.dollars(value.as(Double.self) ?? 0)) }
            }
        }
        .frame(height: 40)
    }
}
