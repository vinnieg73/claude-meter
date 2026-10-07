import Charts
import SwiftUI

/// This week's climb against an even pace to the reset, and where the average pace lands.
struct HistoryWeekChart: View {
    let h: History

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("This week").font(.headline)
                Spacer()
                Text(summary).font(.caption).foregroundStyle(.secondary)
            }
            if let start = h.weekStart, let end = h.weekEnd {
                Chart {
                    RuleMark(y: .value("Cap", 100))
                        .foregroundStyle(Color.red.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    ForEach([PacePoint(at: start, pct: 0), PacePoint(at: end, pct: 100)], id: \.at) { p in
                        LineMark(x: .value("Time", p.at), y: .value("Used", p.pct), series: .value("Series", "even"))
                            .foregroundStyle(Color.secondary.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 4]))
                    }
                    ForEach(Array(h.weekSeries.enumerated()), id: \.offset) { _, p in
                        AreaMark(x: .value("Time", p.at), y: .value("Used", p.pct))
                            .foregroundStyle(Color.accentColor.opacity(0.15))
                        LineMark(x: .value("Time", p.at), y: .value("Used", p.pct), series: .value("Series", "used"))
                            .foregroundStyle(Color.accentColor)
                    }
                    if let now = h.weekSeries.last, let atReset = h.weekAtReset {
                        ForEach([now, PacePoint(at: end, pct: atReset)], id: \.at) { p in
                            LineMark(x: .value("Time", p.at), y: .value("Used", min(p.pct, 150)),
                                     series: .value("Series", "pace"))
                                .foregroundStyle(atReset >= 100 ? Color.orange : Color.secondary)
                                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        }
                    }
                }
                .chartXScale(domain: start...end)
                .chartYScale(domain: 0...max(110, min(h.weekAtReset ?? 0, 150)))
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing, values: [0, 50, 100]) { value in
                        AxisGridLine()
                        AxisValueLabel { Text("\(value.as(Int.self) ?? 0)%") }
                    }
                }
                .frame(height: 130)
                Text("Dotted grey: an even pace to the reset. Dashed: where your average pace lands.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("No weekly reading yet.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var summary: String {
        guard let now = h.weekNow, let start = h.weekStart, let end = h.weekEnd else { return "" }
        let even = Date().timeIntervalSince(start) / end.timeIntervalSince(start) * 100
        let gap = now - even
        var parts = ["\(Fmt.pct(now)) used"]
        parts.append(abs(gap) < 2 ? "on an even pace"
                     : "\(Fmt.pct(abs(gap))) \(gap > 0 ? "ahead of" : "behind") an even pace")
        if let atReset = h.weekAtReset { parts.append("~\(Fmt.pct(atReset)) by reset") }
        return parts.joined(separator: " · ")
    }
}
