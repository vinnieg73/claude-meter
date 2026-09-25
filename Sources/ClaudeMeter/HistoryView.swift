import Charts
import SwiftUI

/// The History window: the last week of 5-hour windows, this week's climb against an even pace,
/// and how the same usage would have gone on each plan.
struct HistoryView: View {
    @ObservedObject var meter: Meter

    var body: some View {
        let h = meter.history()
        VStack(alignment: .leading, spacing: 18) {
            windows(h)
            Divider()
            week(h)
            Divider()
            plans(h)
            Text(footnote(h))
                .font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(width: 560)
    }

    private func windows(_ h: History) -> some View {
        let recent = h.windows.filter { $0.end > Date().addingTimeInterval(-7 * 86400) }
        let capped = recent.filter { $0.peak >= 100 }.count
        let peak = recent.map(\.peak).max() ?? 0
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("5-hour windows · last 7 days").font(.headline)
                Spacer()
                Text("\(recent.count) windows · capped \(capped)× · busiest \(Self.peak(peak))")
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

    private func week(_ h: History) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("This week").font(.headline)
                Spacer()
                Text(weekSummary(h)).font(.caption).foregroundStyle(.secondary)
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

    private func plans(_ h: History) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Plan fit").font(.headline)
                Spacer()
                Picker("Your plan", selection: $meter.plan) {
                    ForEach(Plan.allCases) { Text($0.name).tag($0) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                GridRow {
                    Text("")
                    Text("Capped (7 days)")
                    Text("Busiest window")
                    Text("Weekly limit at your average")
                }
                .font(.caption).foregroundStyle(.secondary)
                ForEach(h.plans) { p in
                    GridRow {
                        Text(p.plan.name + (p.current ? " (you)" : "")).fontWeight(p.current ? .semibold : .regular)
                        Text(p.capped == 0 ? "never" : "\(p.capped)×")
                            .foregroundStyle(p.capped == 0 ? Color.primary : Color.orange)
                        Text(Self.peak(p.peak)).foregroundStyle(p.peak >= 100 ? Color.orange : Color.primary)
                        if p.weekOver {
                            Text("already over").foregroundStyle(Color.orange)
                        } else if let out = p.weekRunsOut {
                            Text("runs out \(Fmt.when(out))").foregroundStyle(Color.orange)
                        } else {
                            Text(p.weekAtReset.map { "~\(Fmt.pct($0)) at reset" } ?? "–")
                        }
                    }
                    .font(.callout).monospacedDigit()
                }
            }
            Text(verdict(h)).font(.callout).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// What happened on the current plan, and the smallest plan that would have covered it.
    private func verdict(_ h: History) -> String {
        func fits(_ p: PlanFit) -> Bool { p.capped == 0 && p.weekRunsOut == nil && !p.weekOver }
        guard let current = h.plans.first(where: \.current) else { return "" }
        if fits(current) {
            let smaller = h.plans.filter { $0.plan.multiplier < current.plan.multiplier && fits($0) }
                .max { $0.plan.multiplier < $1.plan.multiplier }
            if let smaller { return "\(smaller.plan.name) would have covered this week too." }
            return "\(current.plan.name) has covered this week, and this pace stays inside it."
        }
        var trouble: [String] = []
        if current.capped > 0 { trouble.append("\(current.capped) window\(current.capped == 1 ? "" : "s") capped") }
        if current.weekOver { trouble.append("the weekly limit is already spent") }
        if let out = current.weekRunsOut { trouble.append("the weekly limit runs out \(Fmt.when(out)) at your average pace") }
        var text = "On \(current.plan.name): " + trouble.joined(separator: ", ") + "."
        if let bigger = h.plans.filter({ $0.plan.multiplier > current.plan.multiplier && fits($0) })
            .min(by: { $0.plan.multiplier < $1.plan.multiplier }) {
            text += " \(bigger.plan.name) would have covered it."
        }
        return text
    }

    private func weekSummary(_ h: History) -> String {
        guard let now = h.weekNow, let start = h.weekStart, let end = h.weekEnd else { return "" }
        let even = Date().timeIntervalSince(start) / end.timeIntervalSince(start) * 100
        let gap = now - even
        var parts = ["\(Fmt.pct(now)) used"]
        parts.append(abs(gap) < 2 ? "on an even pace"
                     : "\(Fmt.pct(abs(gap))) \(gap > 0 ? "ahead of" : "behind") an even pace")
        if let atReset = h.weekAtReset { parts.append("~\(Fmt.pct(atReset)) by reset") }
        return parts.joined(separator: " · ")
    }

    private func footnote(_ h: History) -> String {
        var text = "Estimates use this Mac's Claude Code logs and today's calibration; claude.ai chat and other devices only show up in exact readings. Days spent on other models (Opus 5 before Sep 22, Fable) are priced differently and may read high."
        if let since = h.exactSince { text += " Exact readings logged since \(Fmt.when(since))." }
        text += " Plan fit assumes each plan's limits scale with its multiplier (Pro 1×, Max 5×, Max 20×)."
        return text
    }

    /// Usage stops at the cap, so anything past it is an estimate overshooting; say "100%+".
    static func peak(_ value: Double) -> String { value >= 100 ? "100%+" : Fmt.pct(value) }

    private func color(_ peak: Double) -> Color {
        peak >= 100 ? .red : peak >= 70 ? .orange : .accentColor
    }
}
