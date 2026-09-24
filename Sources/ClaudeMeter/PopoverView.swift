import Charts
import SwiftUI

struct PopoverView: View {
    @ObservedObject var meter: Meter

    var body: some View {
        let s = meter.snapshot
        VStack(alignment: .leading, spacing: 10) {
            header(s)

            if !s.loaded {
                ProgressView("Reading Claude Code logs…").controlSize(.small)
            } else {
                if let w = s.fiveHour { WindowCard(w: w) }
                if let w = s.weekly {
                    VStack(alignment: .leading, spacing: 3) {
                        WindowCard(w: w)
                        ForEach(s.extras, id: \.title) { x in
                            HStack {
                                Text(x.title)
                                Spacer()
                                Text(Fmt.pct(x.pct)).monospacedDigit()
                            }
                            .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                if s.fiveHour == nil {
                    Text("No limit reading yet. Press Sync to take one.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !s.burning.isEmpty {
                    Divider()
                    burning(s)
                }
                Divider()
                today(s)
            }

            Divider()
            footer(s)
        }
        .padding(14)
        .frame(width: 340)
    }

    private func header(_ s: Snapshot) -> some View {
        HStack {
            Text("Claude usage").font(.headline)
            Spacer()
            if s.activeCount > 0 {
                HStack(spacing: 4) {
                    Circle().fill(.green).frame(width: 6, height: 6)
                    Text("\(s.activeCount) active").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func burning(_ s: Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text("Burning now").font(.subheadline.weight(.semibold))
                Spacer()
                let total = s.burning.reduce(0) { $0 + $1.perHour }
                let pct = s.burning.compactMap(\.pctPerHour).reduce(0, +)
                Text("\(Fmt.dollars(total))/hr" + (s.calibrated ? " · +\(Fmt.rate(pct))%/hr" : ""))
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
            .help("Spend over the last 15 minutes. %/hr is of the 5-hour window.")
            ForEach(s.burning.prefix(4)) { b in
                HStack(spacing: 6) {
                    Text(b.name).lineLimit(1).truncationMode(.tail)
                    Text(b.model).foregroundStyle(.tertiary).lineLimit(1)
                    Spacer(minLength: 4)
                    Text("\(Fmt.dollars(b.perHour))/hr").monospacedDigit()
                    if let p = b.pctPerHour {
                        Text("+\(Fmt.rate(p))%/hr").monospacedDigit().foregroundStyle(.secondary)
                            .frame(width: 58, alignment: .trailing)
                    }
                }
                .font(.caption)
            }
        }
    }

    private func today(_ s: Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("Today").font(.subheadline.weight(.semibold))
                Spacer()
                let hit = s.cacheHit.map { " · cache \(Fmt.pct($0 * 100))" } ?? ""
                Text("\(Fmt.dollars(s.todayCost)) API-equiv · \(Fmt.tokens(s.todayTokens)) tok\(hit)")
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }

            // Each project's share of today, drawn behind its row.
            let top = max(s.projects.first?.cost ?? 1, 0.01)
            ForEach(s.projects.prefix(4)) { row in
                HStack {
                    Text(row.id).lineLimit(1)
                    Spacer()
                    Text(Fmt.dollars(row.cost)).monospacedDigit().foregroundStyle(.secondary)
                }
                .font(.caption)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(alignment: .leading) {
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.accentColor.opacity(0.22))
                            .frame(width: max(3, geo.size.width * row.cost / top))
                    }
                }
            }

            if s.models.count > 1 {
                Text(s.models.prefix(3).map { "\($0.id) \(Fmt.dollars($0.cost))" }.joined(separator: " · "))
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }

            Chart(s.daily) { bar in
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
            .padding(.top, 4)
        }
    }

    private func footer(_ s: Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(sources(s))
                .font(.caption2).foregroundStyle(s.probeStatus == nil ? .secondary : Color.orange)
                .fixedSize(horizontal: false, vertical: true)
            ForEach([meter.loginError, meter.notice].compactMap { $0 }, id: \.self) { message in
                Text(message).font(.caption2).foregroundStyle(.red)
            }
            HStack {
                Button(s.probing ? "Syncing…" : "Sync") { meter.sync(force: true) }
                    .disabled(s.probing)
                Menu {
                    Toggle("Open at login", isOn: Binding(get: { meter.launchAtLogin },
                                                          set: { meter.setLaunchAtLogin($0) }))
                    Toggle("Weekly % in menu bar", isOn: $meter.showWeeklyInTitle)
                    Toggle("Notifications", isOn: $meter.notificationsOn)
                    Button("Send test notification") { meter.testNotification() }
                    Divider()
                    Text("Claude Meter \(Meter.version)")
                } label: {
                    Image(systemName: "gearshape")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .controlSize(.small)
        }
    }

    private func sources(_ s: Snapshot) -> String {
        if let failure = s.probeStatus { return failure }
        var parts = ["Exact every 15 min while you work", "~ = estimated in between"]
        if let tap = s.tapSeen { parts.append("statusline \(Fmt.ago(tap))") }
        if !s.calibrated { parts.append("not calibrated yet") }
        return parts.joined(separator: " · ")
    }
}

private struct WindowCard: View {
    let w: WindowView

    private var color: Color {
        switch w.level {
        case .critical: .red
        case .warn: .orange
        case .normal: .accentColor
        }
    }

    /// "exact · 2m ago", or "est. ±0.7 · 12m ago" counting from the last exact reading.
    private var status: String? {
        guard let asOf = w.asOf else { return nil }
        if w.exact { return "exact · \(Fmt.ago(asOf))" }
        return ["est.", w.accuracy].compactMap { $0 }.joined(separator: " ") + " · \(Fmt.ago(asOf))"
    }

    private var tooltip: String {
        guard let asOf = w.asOf, !w.exact else { return "Exact reading." }
        let base = "Estimated from this Mac's logs since the last exact reading \(Fmt.ago(asOf))."
        return [base, w.accuracyDetail].compactMap { $0 }.joined(separator: " ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(w.title).font(.subheadline.weight(.semibold))
                Spacer()
                Text((w.exact ? "" : "~") + Fmt.pct(w.pct))
                    .font(.title3.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(color)
            }
            if w.series.count > 1, w.start != nil {
                PaceChart(w: w, color: color)
            } else {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.2))
                        Capsule().fill(color).frame(width: geo.size.width * min(w.pct, 100) / 100)
                    }
                }
                .frame(height: 5)
            }
            HStack {
                if w.idle {
                    Text("Idle. Next message opens a window.")
                } else if let r = w.resetsAt {
                    Text("Resets \(Fmt.when(r)) · \(Fmt.duration(r.timeIntervalSinceNow))")
                }
                Spacer(minLength: 6)
                if let status {
                    Text(status).foregroundStyle(.tertiary).help(tooltip)
                }
            }
            if let p = w.projection {
                Text(p).foregroundStyle(w.projectionWarn ? Color.orange : Color.secondary)
            }
        }
        .font(.caption)
    }
}

/// The 5-hour window so far, the pace line to its reset, and the cap.
private struct PaceChart: View {
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
