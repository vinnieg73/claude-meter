import Charts
import SwiftUI

/// Every 5-hour window of the last 7 days, as high as it got.
struct HistoryWindowsChart: View {
    let h: History
    @Environment(\.colorScheme) private var scheme

    /// The plot is this tall in points and spans 0...`ceiling` in %, so a point is a point of %. The
    /// room above the cap line holds its label.
    private static let plotHeight: CGFloat = 114
    private static let ceiling = 114.0
    /// What a bar shows at most: an estimate past the cap pokes a little above the line.
    private static let barMax = 105.0
    /// Bars reach this far below the floor and the plot clips them there, so only the tops are rounded.
    private static let sink = 6.0
    /// A little off each side of a bar, so windows that follow each other don't fuse into one.
    private static let inset: TimeInterval = 12 * 60

    var body: some View {
        let now = Date()
        let from = now.addingTimeInterval(-7 * 86400)
        let to = now.addingTimeInterval(3600)
        let recent = h.windows.filter { $0.end > from }
        let capped = recent.filter { $0.peak >= 100 }.count
        let peak = recent.map(\.peak).max() ?? 0
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                ModuleTitle(symbol: "clock", title: "5-hour windows · last 7 days")
                Spacer(minLength: 8)
                HStack(spacing: 6) {
                    Chip(text: recent.count == 1 ? "1 window" : "\(recent.count) windows")
                    Chip(text: "capped \(capped)×", tint: capped > 0 ? .orange : .secondary)
                    Chip(text: "busiest \(HistoryView.peak(peak))", tint: peak >= 100 ? .orange : .secondary)
                }
                .accessibilityElement(children: .combine)
            }
            chart(recent, from: from, to: to)
            legend
        }
    }

    private func chart(_ windows: [HistoryWindow], from: Date, to: Date) -> some View {
        // The "cap" label sits above the line at the left. A capped bar pokes above the line, so
        // one there would cover the label: it moves to the right end (and stays put if a capped
        // bar is there too).
        let reach: TimeInterval = 8 * 3600
        func cappedBar(_ w: HistoryWindow, between a: Date, and b: Date) -> Bool {
            w.peak >= 100 && w.end > a && w.start < b
        }
        let labelAtEnd = windows.contains { cappedBar($0, between: from, and: from.addingTimeInterval(reach)) }
            && !windows.contains { cappedBar($0, between: to.addingTimeInterval(-reach), and: to) }
        return Chart {
            RuleMark(y: .value("Cap", 100))
                .foregroundStyle(Color.red.opacity(0.45))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .annotation(position: .top, alignment: labelAtEnd ? .trailing : .leading, spacing: 1) {
                    Text("cap").font(.system(size: 9, weight: .medium)).foregroundStyle(Color.red.opacity(0.9))
                        .accessibilityHidden(true)
                }
                .accessibilityLabel("Cap")
                .accessibilityValue("100%")
            ForEach(windows) { bar($0) }
        }
        .chartXScale(domain: from...to)
        .chartYScale(domain: 0...Self.ceiling)
        // Clipped: a window straddling the 7-day mark starts off the chart.
        .chartPlotStyle { $0.frame(height: Self.plotHeight).clipped() }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Theme.track)
                AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                    .font(.system(size: 10)).foregroundStyle(Color.secondary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: [0, 50, 100]) { value in
                if value.as(Int.self) != 100 { // the cap line is drawn there
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Theme.track)
                }
                AxisValueLabel { Text("\(value.as(Int.self) ?? 0)%") }
                    .font(.system(size: 10).monospacedDigit()).foregroundStyle(Color.secondary)
            }
        }
        .overlay {
            if !h.calibrated {
                Label("Needs one exact reading to calibrate first.", systemImage: "speedometer")
                    .font(Theme.row).foregroundStyle(.secondary)
                    .padding(.bottom, 14) // centred on the plot, not on the axis labels under it
            }
        }
        .help("Each bar spans a window, as high as it got.")
    }

    /// One window: a rounded bar from when it opened to when it resets. Solid when an exact
    /// reading backs it; faded, with a solid top edge, when it's estimated from the logs.
    @ChartContentBuilder
    private func bar(_ w: HistoryWindow) -> some ChartContent {
        let top = min(w.peak, Self.barMax)
        let inset = min(Self.inset, w.end.timeIntervalSince(w.start) / 4) // a window cut short stays a bar
        RectangleMark(xStart: .value("Opened", w.start.addingTimeInterval(inset)),
                      xEnd: .value("Reset", w.end.addingTimeInterval(-inset)),
                      yStart: .value("Floor", -Self.sink), yEnd: .value("Peak", top))
            .cornerRadius(3)
            .foregroundStyle(WindowBarFill(color: Theme.color(level(w.peak)), exact: w.exact, dark: scheme == .dark)
                .gradient(heightInPoints: top + Self.sink))
            .accessibilityLabel("Window opened \(Fmt.when(w.start))")
            .accessibilityValue("peak \(HistoryView.peak(w.peak)), \(w.exact ? "exact reading" : "estimated from the logs")")
    }

    /// Red is a window that hit the cap, as the line and the "capped" count say; orange is one that got hot.
    private func level(_ peak: Double) -> Level { peak >= 100 ? .critical : peak >= 70 ? .warn : .normal }

    private var legend: some View {
        HStack(spacing: 12) {
            LegendKey(exact: true, text: "Exact reading")
            LegendKey(exact: false, text: "Estimated from logs")
            Spacer(minLength: 0)
            Text("Estimates past 100% almost certainly hit the cap.")
        }
        .font(Theme.meta).foregroundStyle(.secondary)
        .lineLimit(1)
    }
}

/// How a window's bar is filled, so the chart and its legend draw it the same way. Exact: a solid
/// gradient. Estimated: the same colour faded, with the top edge kept solid.
private struct WindowBarFill {
    let color: Color
    let exact: Bool
    let dark: Bool

    /// `heightInPoints` is the shape's height, so the solid edge is as thick on every bar.
    func gradient(heightInPoints: Double) -> LinearGradient {
        if exact {
            return LinearGradient(colors: [color, color.opacity(0.8)], startPoint: .top, endPoint: .bottom)
        }
        let edge = min(1, 1.75 / max(heightInPoints, 1))
        let body = dark ? (top: 0.6, bottom: 0.25) : (top: 0.5, bottom: 0.15)
        return LinearGradient(stops: [
            .init(color: color, location: 0),
            .init(color: color, location: edge),
            .init(color: color.opacity(body.top), location: edge),
            .init(color: color.opacity(body.bottom), location: 1),
        ], startPoint: .top, endPoint: .bottom)
    }
}

/// A legend entry: a small bar drawn the way the chart draws one.
private struct LegendKey: View {
    let exact: Bool
    let text: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(WindowBarFill(color: .accentColor, exact: exact, dark: scheme == .dark).gradient(heightInPoints: 8))
                .frame(width: 10, height: 8)
                .accessibilityHidden(true)
            Text(text)
        }
    }
}
