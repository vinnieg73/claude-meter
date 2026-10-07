import SwiftUI

/// How the same usage would have gone on each plan, and which plan covers it.
struct PlanFitSection: View {
    let h: History
    @Binding var plan: Plan

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Plan fit").font(.headline)
                Spacer()
                Picker("Your plan", selection: $plan) {
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
                        Text(HistoryView.peak(p.peak)).foregroundStyle(p.peak >= 100 ? Color.orange : Color.primary)
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
            Text(verdict).font(.callout).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// What happened on the current plan, and the smallest plan that would have covered it.
    private var verdict: String {
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
}

/// What the History estimates rest on.
struct HistoryFootnote: View {
    let h: History

    var body: some View {
        Text(text)
            .font(.caption2).foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var text: String {
        var text = "Estimates use this Mac's Claude Code logs and today's calibration; claude.ai chat and other devices only show up in exact readings. Days spent on other models (Opus 5 before Sep 22, Fable) are priced differently and may read high."
        if let since = h.exactSince { text += " Exact readings logged since \(Fmt.when(since))." }
        text += " Plan fit assumes each plan's limits scale with its multiplier (Pro 1×, Max 5×, Max 20×)."
        return text
    }
}
