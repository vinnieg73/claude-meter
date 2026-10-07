import Charts
import SwiftUI

/// The 5-hour window so far, the pace line to its reset, and the cap.
struct PaceChart: View {
    let w: WindowView
    let color: Color

    var body: some View {
        let start = w.start ?? Date()
        let end = max(w.resetsAt ?? Date(), start.addingTimeInterval(60))
        // Scaled to where the window is heading, so a quiet window isn't an empty box.
        // The cap line appears once the window is heading anywhere near it.
        let peak = max(w.pct, w.pace.map(\.pct).max() ?? 0)
        let top = peak >= 70 ? max(100, peak) : max(20, peak * 1.3)
        Chart {
            if top >= 100 {
                RuleMark(y: .value("Cap", 100))
                    .foregroundStyle(Color.red.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
            }
            ForEach(Array(w.series.enumerated()), id: \.offset) { _, p in
                AreaMark(x: .value("Time", p.at), y: .value("Used", p.pct))
                    .foregroundStyle(color.opacity(0.15))
                LineMark(x: .value("Time", p.at), y: .value("Used", p.pct), series: .value("Series", "used"))
                    .foregroundStyle(color)
            }
            ForEach(Array(w.pace.enumerated()), id: \.offset) { _, p in
                LineMark(x: .value("Time", p.at), y: .value("Used", p.pct), series: .value("Series", "pace"))
                    .foregroundStyle(w.projectionWarn ? Color.orange : Color.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
            }
        }
        .chartXScale(domain: start...end)
        .chartYScale(domain: 0...top)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartPlotStyle { $0.background(Color.secondary.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 4)) }
        .frame(height: 34)
    }
}
