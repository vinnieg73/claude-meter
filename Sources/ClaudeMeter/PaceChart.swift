import Charts
import SwiftUI

/// The 5-hour window so far, the pace line to its reset, and the cap.
struct PaceChart: View {
    let w: WindowView
    let color: Color

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let start = w.start ?? Date()
        let now = w.series.last
        let end = max(w.resetsAt ?? Date(), start.addingTimeInterval(60), now?.at ?? start, w.pace.last?.at ?? start)
        // Scaled to where the window is heading, so a quiet window isn't an empty box.
        // The cap line appears once the window is heading anywhere near it.
        let peak = max(w.pct, w.pace.map(\.pct).max() ?? 0)
        let top = peak >= 70 ? max(100, peak) : max(20, peak * 1.3)
        let strong = contrast == .increased
        Chart {
            if top >= 100 {
                RuleMark(y: .value("Cap", 100))
                    .foregroundStyle(Color.red.opacity(strong ? 0.8 : 0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            ForEach(Array(w.series.enumerated()), id: \.offset) { _, p in
                AreaMark(x: .value("Time", p.at), y: .value("Used", p.pct))
                    .foregroundStyle(LinearGradient(colors: [color.opacity(0.32), color.opacity(0.03)],
                                                    startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Time", p.at), y: .value("Used", p.pct), series: .value("Series", "used"))
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 1.75, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
            }
            ForEach(Array(w.pace.enumerated()), id: \.offset) { _, p in
                LineMark(x: .value("Time", p.at), y: .value("Used", p.pct), series: .value("Series", "pace"))
                    .foregroundStyle(w.projectionWarn ? Color.orange : Color.secondary.opacity(strong ? 1 : 0.8))
                    .lineStyle(StrokeStyle(lineWidth: 1.25, lineCap: .round, dash: [2.5, 3]))
            }
            // Where the window is now: a dot in a soft halo (two discs, so it fades rather than ends).
            if let now {
                PointMark(x: .value("Time", now.at), y: .value("Used", now.pct))
                    .symbolSize(100).foregroundStyle(color.opacity(0.10))
                PointMark(x: .value("Time", now.at), y: .value("Used", now.pct))
                    .symbolSize(56).foregroundStyle(color.opacity(0.18))
                PointMark(x: .value("Time", now.at), y: .value("Used", now.pct))
                    .symbolSize(22).foregroundStyle(color)
            }
        }
        .chartXScale(domain: start...end)
        // Room inside the plot, so the line at 0%, and the dot and the cap line at 100%, aren't cut.
        .chartYScale(domain: 0...top, range: .plotDimension(startPadding: 3, endPadding: 5))
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(values: [0.25, 0.5, 0.75].map { $0 * min(top, 100) }) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(strong ? Theme.quiet : Theme.track)
            }
        }
        .chartPlotStyle { $0.clipShape(PlotClip()) }
        .frame(height: 38)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isImage)
        .accessibilityLabel(summary)
    }

    /// The plot's rectangle with a little extra at the sides, so the dot isn't sliced in the first
    /// and last minutes of a window. Top and bottom stay exact: nothing spills past them.
    private struct PlotClip: Shape {
        func path(in rect: CGRect) -> Path { Path(rect.insetBy(dx: -6, dy: 0)) }
    }

    /// What the drawing shows, for VoiceOver: where the window is now and where its pace goes.
    private var summary: String {
        var text = "5-hour window usage so far, \(w.exact ? "" : "about ")\(Fmt.pct(w.pct))"
        if !w.pace.isEmpty {
            if let capAt = w.capAt {
                text += ". At this pace it reaches the cap at \(Fmt.when(capAt))"
            } else if let atReset = w.atReset {
                text += ". At this pace about \(Fmt.pct(atReset)) by the reset"
            }
        }
        return text
    }
}
