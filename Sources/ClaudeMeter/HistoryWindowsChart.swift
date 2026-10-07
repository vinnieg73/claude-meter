import Charts
import SwiftUI

/// Every 5-hour window of the last 7 days, as high as it got.
struct HistoryWindowsChart: View {
    let h: History

    var body: some View {
        let recent = h.windows.filter { $0.end > Date().addingTimeInterval(-7 * 86400) }
        let capped = recent.filter { $0.peak >= 100 }.count
        let peak = recent.map(\.peak).max() ?? 0
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("5-hour windows · last 7 days").font(.headline)
                Spacer()
                Text("\(recent.count) windows · capped \(capped)× · busiest \(HistoryView.peak(peak))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !h.calibrated {
                Text("Needs one exact reading to calibrate first.").font(.caption).foregroundStyle(.secondary)
            }
            Chart {
                RuleMark(y: .value("Cap", 100))
                    .foregroundStyle(Color.red.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                ForEach(recent) { w in
                    RectangleMark(xStart: .value("Opened", w.start), xEnd: .value("Reset", w.end),
                                  yStart: .value("Floor", 0), yEnd: .value("Peak", min(w.peak, 105)))
                        .foregroundStyle(color(w.peak).opacity(w.exact ? 0.9 : 0.45))
                }
            }
            .chartXScale(domain: Date().addingTimeInterval(-7 * 86400)...Date().addingTimeInterval(3600))
            .chartPlotStyle { $0.clipped() } // a window straddling the 7-day mark starts off the chart
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                }
            }
            .chartYScale(domain: 0...110)
            .chartYAxis {
                AxisMarks(position: .trailing, values: [0, 50, 100]) { value in
                    AxisGridLine()
                    AxisValueLabel { Text("\(value.as(Int.self) ?? 0)%") }
                }
            }
            .frame(height: 130)
            Text("Each bar spans a window, as high as it got. Solid: backed by an exact reading. Faded: estimated from the logs. An estimate past 100% means the window almost certainly hit the cap.")
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func color(_ peak: Double) -> Color {
        peak >= 100 ? .red : peak >= 70 ? .orange : .accentColor
    }
}
