import SwiftUI

/// Sessions spending right now, and quiet ones whose prompt cache is about to expire.
struct SessionsSection: View {
    let s: Snapshot

    var body: some View {
        if !s.burning.isEmpty { burning }
        if !s.cooling.isEmpty { cooling }
    }

    private var burning: some View {
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
                let runaway = s.runaways.first { $0.id == b.id }
                HStack(spacing: 6) {
                    if runaway != nil {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                            .help("Used \(Fmt.pct(runaway?.pct ?? 0)) of the 5-hour window in the last 30 minutes.")
                    }
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

    private var cooling: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Going cold").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .help("Idle sessions whose prompt cache expires soon. After that, their next message "
                      + "re-writes the whole context instead of reading it from cache.")
            ForEach(s.cooling.prefix(3)) { c in
                HStack(spacing: 6) {
                    Text(c.name).lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 4)
                    Text("cold in \(Fmt.duration(c.coldAt.timeIntervalSinceNow))").foregroundStyle(.secondary)
                    Text("then +\(Fmt.dollars(c.extra))" + (c.extraPct.map { " (+\(Fmt.rate($0))%)" } ?? ""))
                        .monospacedDigit()
                }
                .font(.caption)
            }
        }
    }
}
