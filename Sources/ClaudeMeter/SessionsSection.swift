import AppKit
import SwiftUI

/// Sessions spending right now, and quiet ones whose prompt cache is about to expire: the content
/// of one module, "Burning now" over "Going cold".
struct SessionsSection: View {
    let s: Snapshot

    /// Where a row's text starts, from the module's edge: `BarRow`'s padding, or, when the list keeps
    /// a column for the warning, in line with the module title's text (its symbol column and gap).
    fileprivate enum Inset {
        static let plain: CGFloat = 6
        static let warned: CGFloat = 13 + 5
    }

    var body: some View {
        let rows = Array(s.burning.prefix(4))
        // What each runaway's warning says, by session (the first one, should an id repeat).
        let warnings = Dictionary(s.runaways.map {
            ($0.id, "Used \(Fmt.pct($0.pct)) of the 5-hour window in the last 30 minutes.")
        }, uniquingKeysWith: { first, _ in first })
        // One shared column for the warning, so every name stays aligned when a row has it.
        let warned = rows.contains { warnings[$0.id] != nil }

        VStack(alignment: .leading, spacing: 0) {
            if !rows.isEmpty { burning(rows, warnings: warnings, warned: warned) }
            if !rows.isEmpty && !s.cooling.isEmpty {
                // More room above than below: the title under it carries its own leading.
                Rectangle().fill(Theme.hairline).frame(height: 0.5)
                    .padding(.top, 4).padding(.bottom, 1.5)
                    .accessibilityHidden(true)
            }
            if !s.cooling.isEmpty { cooling(warned: warned) }
        }
    }

    // MARK: - Burning now

    private func burning(_ rows: [Burn], warnings: [String: String], warned: Bool) -> some View {
        let top = rows.map(\.perHour).max() ?? 1
        let total = s.burning.reduce(0) { $0 + $1.perHour }
        let pct = s.burning.compactMap(\.pctPerHour).reduce(0, +)

        return VStack(alignment: .leading, spacing: 2) {
            // Last baseline: the title's own, not its symbol's.
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                ModuleTitle(symbol: "flame.fill", title: "Burning now", tint: .orange)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Text("\(Fmt.dollars(total))/hr" + (s.calibrated ? " · +\(Fmt.rate(pct))%/hr" : ""))
                    .font(Theme.meta).monospacedDigit().foregroundStyle(.secondary)
                    .accessibilityLabel("\(Fmt.dollars(total)) per hour"
                                        + (s.calibrated ? ", plus \(Fmt.rate(pct)) percent of the 5-hour window per hour" : ""))
            }
            .help("Spend over the last 15 minutes. %/hr is of the 5-hour window.")

            VStack(spacing: 1) {
                ForEach(rows) { b in
                    SessionRow(name: b.name, model: b.model, tag: b.tag,
                               figure: Fmt.dollars(b.perHour),
                               detail: b.pctPerHour.map { "+\(Fmt.rate($0))%" },
                               fraction: top > 0 ? b.perHour / top : 0,
                               warning: warnings[b.id],
                               warned: warned)
                }
            }
        }
    }

    // MARK: - Going cold

    private func cooling(warned: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 0) {
                ModuleTitle(symbol: "snowflake", title: "Going cold", tint: .cyan)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
            }
            .help("Idle sessions whose prompt cache expires soon. After that, their next message "
                  + "re-writes the whole context instead of reading it from cache.")

            // A grid, so the chips and the costs line up from row to row.
            Grid(alignment: .trailing, horizontalSpacing: 6, verticalSpacing: 2) {
                ForEach(s.cooling.prefix(3)) { c in
                    let left = c.coldAt.timeIntervalSinceNow
                    let cold = left < 60 ? "cold in <1m" : "cold in \(Fmt.duration(left))"
                    let extra = Fmt.dollars(c.extra)
                    let extraPct = c.extraPct.map { "(+\(Fmt.rate($0))%)" }
                    GridRow(alignment: .firstTextBaseline) {
                        // A row's modifiers land on each of its cells, so the one spoken description
                        // sits on the first cell and the others stay silent.
                        // The name gives way to the tag, which is short and shown whole.
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(c.name).lineLimit(1).truncationMode(.tail)
                            if let tag = c.tag {
                                Text("· \(tag)").font(Theme.meta).foregroundStyle(.secondary).lineLimit(1).fixedSize()
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .help(c.name + (c.tag.map { "\n" + tagTip($0) } ?? ""))
                        .accessibilityElement(children: .ignore)
                        .accessibilityAddTraits(.isStaticText)
                        .accessibilityLabel("\(c.name)\(c.tag.map { ", " + tagTip($0) } ?? ""), \(cold), then plus \(extra)"
                                            + (c.extraPct.map { ", plus \(Fmt.rate($0)) percent" } ?? ""))
                        ColdChip(text: cold)
                            .accessibilityHidden(true)
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text("then").font(Theme.meta).foregroundStyle(.secondary)
                            Text("+\(extra)")
                            if let extraPct {
                                Text(extraPct).font(Theme.meta).foregroundStyle(.secondary)
                            }
                        }
                        .monospacedDigit()
                        .fixedSize()
                        .accessibilityHidden(true)
                    }
                    .font(Theme.row)
                }
            }
            .padding(.leading, warned ? Inset.warned : Inset.plain)
            .padding(.trailing, 6)
        }
    }
}

/// A burning session: its share of the spend drawn behind it (the same bar as `BarRow`), the model in
/// its tooltip, and a warning ahead of it for a runaway.
private struct SessionRow: View {
    let name: String
    let model: String
    /// When the session last ran, after the name, while another row shares its name.
    let tag: String?
    let figure: String
    let detail: String?
    /// 0...1 of the row's width.
    let fraction: Double
    /// Set for a runaway: what the warning says.
    let warning: String?
    /// Whether the list keeps a column for the warning (some row in it has one).
    let warned: Bool

    private static let gap: CGFloat = 6
    private static let warningWidth: CGFloat = 8

    var body: some View {
        let tint = Theme.color(warning == nil ? .normal : .warn)
        HStack(alignment: .firstTextBaseline, spacing: Self.gap) {
            if warned {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.color(.warn))
                    .opacity(warning == nil ? 0 : 1)
                    .frame(width: Self.warningWidth)
                    .accessibilityHidden(true)
            }
            // The name has the row to itself (the model is in the tooltip); only the tag, short and shown
            // whole, sits after it.
            Text(name).lineLimit(1).truncationMode(.tail).layoutPriority(1)
            if let tag {
                Text("· \(tag)").font(Theme.meta).foregroundStyle(.secondary)
                    .lineLimit(1).fixedSize()
                    .padding(.leading, 2)
            }
            Spacer(minLength: 4)
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(figure).monospacedDigit()
                Text("/hr").font(Theme.meta).foregroundStyle(.secondary)
            }
            .fixedSize()
            if let detail {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(detail).monospacedDigit()
                    Text("/hr").font(Theme.meta)
                }
                .foregroundStyle(.secondary)
                .fixedSize()
                .frame(minWidth: 54, alignment: .trailing)
            }
        }
        .font(Theme.row)
        .padding(.leading, warned ? SessionsSection.Inset.warned - Self.gap - Self.warningWidth
                                  : SessionsSection.Inset.plain)
        .padding(.trailing, 6)
        .padding(.vertical, 1)
        .background {
            ZStack(alignment: .leading) {
                // A runaway's whole row is tinted, however short its bar.
                if warning != nil {
                    RoundedRectangle(cornerRadius: 4, style: .continuous).fill(tint.opacity(0.07))
                }
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(tint.opacity(warning == nil ? 0.14 : 0.12))
                        .frame(width: max(4, geo.size.width * min(fraction, 1)))
                }
            }
        }
        .modifier(Tip(text: tip))
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isStaticText)
        .accessibilityLabel(label)
    }

    /// The whole name and the model, which the row leaves out, then any tag and warning.
    private var tip: String {
        var lines = ["\(name) · \(model)"]
        if let tag { lines.append(tagTip(tag)) }
        if let warning { lines.append(warning) }
        return lines.joined(separator: "\n")
    }

    private var label: String {
        var parts = [name, model, "\(figure) per hour"]
        if let detail { parts.append("\(detail) of the 5-hour window per hour") }
        if let warning { parts.append("warning: \(warning)") }
        return parts.joined(separator: ", ")
    }
}

/// What a row's tooltip says about its tag: "Last ran 18m ago", "Started 9:41 PM".
private func tagTip(_ tag: String) -> String {
    if tag.hasPrefix("started") { return "S" + tag.dropFirst() }
    return tag == "now" ? "Last ran just now" : "Last ran \(tag) ago"
}

/// The `Chip` look in cyan, with the text darkened in light appearances: system cyan on its own
/// tint is under 2:1 there, too faint for 9.5pt text (the darkened text is about 5:1). Dark
/// appearances keep plain system cyan.
/// Half a point less padding above and below than `Chip`, so it is no taller than the row's text.
private struct ColdChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.chip)
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(Theme.coldText)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(Color.cyan.opacity(0.14)))
    }
}

/// A tooltip when there is something to say.
private struct Tip: ViewModifier {
    let text: String?

    func body(content: Content) -> some View {
        if let text { content.help(text) } else { content }
    }
}
