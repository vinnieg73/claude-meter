import Charts
import SwiftUI

/// This week's climb against an even pace to the reset, and where the average pace lands.
struct HistoryWeekChart: View {
    let h: History
    @Environment(\.colorSchemeContrast) private var contrast

    /// How the two pace lines are drawn. The legend draws its swatches from the same styles.
    private static let evenStroke = StrokeStyle(lineWidth: 1.1, lineCap: .round, dash: [0.1, 3.8])
    private static let averageStroke = StrokeStyle(lineWidth: 1.35, lineCap: .round, dash: [3.2, 3.8])

    /// Increase Contrast firms up what is drawn faintly: the cap line, the gridlines, the even pace.
    private var strong: Bool { contrast == .increased }
    private var evenColor: Color { Color.secondary.opacity(strong ? 1 : 0.75) }
    /// Orange once the average pace reaches the cap.
    private var averageColor: Color { (h.weekAtReset ?? 0) >= 100 ? Theme.color(.warn) : Color.secondary }

    /// The week to draw: nothing without a range, and the empty state stands in.
    private var week: (start: Date, end: Date)? {
        guard let start = h.weekStart, let end = h.weekEnd, end > start else { return nil }
        return (start, end)
    }

    /// Now on the climb, and where the average pace takes it by the reset. Without a pace to
    /// project there is no dashed line, so no legend entry for it either.
    private var average: (now: PacePoint, atReset: Double)? {
        guard let now = h.weekSeries.last, let atReset = h.weekAtReset else { return nil }
        return (now, atReset)
    }

    var body: some View {
        // Spaced as the 5-hour windows chart above it is, so the two modules keep one rhythm.
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                ModuleTitle(symbol: "calendar", title: "This week")
                Spacer(minLength: 0)
                if let summary {
                    // The chart below carries these facts for VoiceOver, spoken properly.
                    Text(summary)
                        .font(Theme.meta).monospacedDigit().foregroundStyle(.secondary)
                        .lineLimit(1)
                        .accessibilityHidden(true)
                }
            }
            if let week {
                chart(from: week.start, to: week.end)
                legend
            } else {
                noReading
            }
        }
    }

    // MARK: - Chart

    /// An estimate far past the cap stops at the top of the chart.
    private static func plotted(_ pct: Double) -> Double { min(pct, 150) }

    private func chart(from start: Date, to end: Date) -> some View {
        let tint = Theme.color(.normal)
        let now = h.weekSeries.last
        // Headroom above whatever is drawn highest: where the average pace lands, or an estimate
        // that has run past the cap.
        let peak = Self.plotted(max(h.weekSeries.map(\.pct).max() ?? 0, h.weekAtReset ?? 0))
        let gridline = strong ? Theme.quiet : Theme.track
        return Chart {
            RuleMark(y: .value("Cap", 100))
                .foregroundStyle(Theme.color(.critical).opacity(strong ? 0.8 : 0.45))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            ForEach(Array([PacePoint(at: start, pct: 0), PacePoint(at: end, pct: 100)].enumerated()),
                    id: \.offset) { _, p in
                LineMark(x: .value("Time", p.at), y: .value("Used", p.pct), series: .value("Series", "even"))
                    .foregroundStyle(evenColor)
                    .lineStyle(Self.evenStroke)
            }
            ForEach(Array(h.weekSeries.enumerated()), id: \.offset) { _, p in
                AreaMark(x: .value("Time", p.at), y: .value("Used", Self.plotted(p.pct)),
                         series: .value("Series", "area"))
                    .foregroundStyle(LinearGradient(colors: [tint.opacity(0.32), tint.opacity(0.03)],
                                                    startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Time", p.at), y: .value("Used", Self.plotted(p.pct)),
                         series: .value("Series", "used"))
                    .foregroundStyle(tint)
                    .lineStyle(StrokeStyle(lineWidth: 1.75, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
            }
            if let average {
                ForEach(Array([average.now, PacePoint(at: end, pct: average.atReset)].enumerated()),
                        id: \.offset) { _, p in
                    LineMark(x: .value("Time", p.at), y: .value("Used", Self.plotted(p.pct)),
                             series: .value("Series", "pace"))
                        .foregroundStyle(averageColor)
                        .lineStyle(Self.averageStroke)
                }
            }
            // Where the week is now: a dot in a soft halo (two discs, so it fades rather than ends),
            // drawn as the 5-hour pace chart draws its own.
            if let now {
                PointMark(x: .value("Time", now.at), y: .value("Used", Self.plotted(now.pct)))
                    .symbolSize(100).foregroundStyle(tint.opacity(0.10))
                PointMark(x: .value("Time", now.at), y: .value("Used", Self.plotted(now.pct)))
                    .symbolSize(56).foregroundStyle(tint.opacity(0.18))
                PointMark(x: .value("Time", now.at), y: .value("Used", Self.plotted(now.pct)))
                    .symbolSize(22).foregroundStyle(tint)
            }
        }
        .chartXScale(domain: start...end)
        .chartYScale(domain: 0...max(110, peak * 1.06))
        // The labels say Color.secondary: inside a chart a bare .secondary resolves against the
        // chart's foreground and comes out blue.
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(gridline)
                // Greedy: a day label that doesn't fit before the reset is dropped, not cut to "W…".
                AxisValueLabel(format: .dateTime.weekday(.abbreviated), collisionResolution: .greedy)
                    .font(Theme.meta).foregroundStyle(Color.secondary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: [0, 50, 100]) { value in
                if value.as(Int.self) != 100 { // the cap line is drawn there
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(gridline)
                }
                AxisValueLabel { Text("\(value.as(Int.self) ?? 0)%") }
                    .font(Theme.meta.monospacedDigit()).foregroundStyle(Color.secondary)
            }
        }
        .frame(height: 130)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isImage)
        .accessibilityLabel("This week's usage against an even pace")
        .accessibilityValue(spoken ?? "")
    }

    // MARK: - Legend

    private var legend: some View {
        HStack(spacing: 12) {
            WeekLegendLine(stroke: Self.evenStroke, tint: evenColor, marks: 5, text: "Even pace to the reset")
            if average != nil {
                WeekLegendLine(stroke: Self.averageStroke, tint: averageColor, marks: 3,
                               text: "Where your average pace lands")
            }
        }
        .font(Theme.meta)
        .foregroundStyle(.secondary)
    }

    // MARK: - No reading

    private var noReading: some View {
        HStack(spacing: 5) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 10, weight: .semibold))
                .accessibilityHidden(true)
            Text("No weekly reading yet.")
        }
        .font(Theme.row)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, minHeight: 36)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.surface))
    }

    // MARK: - Summary

    private var summary: String? {
        guard let now = h.weekNow, let week else { return nil }
        let even = Date().timeIntervalSince(week.start) / week.end.timeIntervalSince(week.start) * 100
        let gap = now - even
        var parts = ["\(Fmt.pct(now)) used"]
        parts.append(abs(gap) < 2 ? "on an even pace"
                     : "\(Fmt.pct(abs(gap))) \(gap > 0 ? "ahead of" : "behind") an even pace")
        if let atReset = h.weekAtReset { parts.append("~\(Fmt.pct(atReset)) by reset") }
        return parts.joined(separator: " · ")
    }

    /// The summary as VoiceOver should read it.
    private var spoken: String? {
        summary?.replacingOccurrences(of: "~", with: "about ").replacingOccurrences(of: " · ", with: ", ")
    }
}

/// A line sample and what it means, drawn the way the chart draws that line. The sample is `marks`
/// dots or dashes long and ends on the last one, so the text sits as far from either kind.
private struct WeekLegendLine: View {
    let stroke: StrokeStyle
    let tint: Color
    let marks: Int
    let text: String

    private var length: CGFloat {
        CGFloat(marks - 1) * stroke.dash.reduce(0, +) + (stroke.dash.first ?? 0)
    }

    var body: some View {
        HStack(spacing: 5) {
            Path { p in
                p.move(to: CGPoint(x: stroke.lineWidth / 2, y: 4))
                p.addLine(to: CGPoint(x: stroke.lineWidth / 2 + length, y: 4))
            }
            .stroke(tint, style: stroke)
            .frame(width: length + stroke.lineWidth, height: 8)
            .accessibilityHidden(true)
            Text(text)
        }
    }
}
