import SwiftUI

/// A limit window: its %, the chart or bar, when it resets, and where the pace takes it.
struct WindowCard: View {
    let w: WindowView

    private var color: Color { Theme.color(w.level) }

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
            if let budget = w.budget {
                Text(budget).foregroundStyle(w.budgetWarn ? Color.orange : Color.secondary)
            }
        }
        .font(.caption)
    }
}

/// Per-model weekly buckets from the last exact reading, under the weekly card.
struct ExtrasRows: View {
    let extras: [WindowView]

    var body: some View {
        ForEach(extras, id: \.title) { x in
            HStack {
                Text(x.title)
                Spacer()
                // Carried over from an older reading: say how old.
                let age = x.asOf.map { Date().timeIntervalSince($0) } ?? 0
                Text(Fmt.pct(x.pct) + (age > 3600 ? " · as of \(Fmt.ago(x.asOf!))" : ""))
                    .monospacedDigit()
            }
            .font(.caption2).foregroundStyle(.secondary)
        }
    }
}
