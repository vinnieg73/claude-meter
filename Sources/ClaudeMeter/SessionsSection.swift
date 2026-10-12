import AppKit
import SwiftUI

/// Sessions spending right now, and quiet ones whose prompt cache is about to expire: the content
/// of one module, "Burning now" over "Going cold".
struct SessionsSection: View {
    let s: Snapshot

    /// Where every row's mascot starts, from the module's edge, so both lists' mascots line up. A
    /// runaway's warning goes after the mascot, in a column Burning now keeps while any row has one.
    fileprivate enum Inset {
        static let lead: CGFloat = 2
        static let warning: CGFloat = 8
        static let gap: CGFloat = 6
    }

    /// The row mascots' scale: 2 points a unit, 32 x 20.
    fileprivate static let mascotScale: CGFloat = 2
    fileprivate static var mascotWidth: CGFloat { CGFloat(Mascot.width) * mascotScale }

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
                Text("Burning now").font(Theme.title)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Text("\(Fmt.dollars(total))/hr" + (s.calibrated ? " · +\(Fmt.rate(pct))%/hr" : ""))
                    .font(Theme.meta).monospacedDigit().foregroundStyle(.secondary)
                    .accessibilityLabel("\(Fmt.dollars(total)) per hour"
                                        + (s.calibrated ? ", plus \(Fmt.rate(pct)) percent of the 5-hour window per hour" : ""))
            }
            .help("Spend over the last 15 minutes. %/hr is of the 5-hour window.")

            VStack(spacing: 1) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, b in
                    SessionRow(phase: Double(i) * Mascot.stagger,name: b.name, model: b.model, tag: b.tag, fable: b.fable,
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
                Text("Going cold").font(Theme.title)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
            }
            .help("Idle sessions whose prompt cache expires soon. After that, their next message "
                  + "re-writes the whole context instead of reading it from cache.")

            VStack(alignment: .leading, spacing: 4) {
                ForEach(s.cooling.prefix(3)) { c in ColdRow(c: c) }
            }
            .padding(.leading, Inset.lead)
            .padding(.trailing, 6)
        }
    }
}

/// A session going cold, on two lines so its name reads whole: a sleeping mascot in its model's
/// muted colour and the name (with any tag), then under the name when it goes cold and what its
/// next message would cost on top of a warm one. The model is in the tooltip.
private struct ColdRow: View {
    let c: Cooling

    /// The mascot's width and the gap after it: where the second line starts.
    private static let gap: CGFloat = 5
    private static var indent: CGFloat { CGFloat(Mascot.width) + gap }

    var body: some View {
        let left = c.coldAt.timeIntervalSinceNow
        let cold = left <= 0 ? "cold now" : "cold in \(Fmt.left(left))"
        let extra = Fmt.dollars(c.extra)
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: Self.gap) {
                Mascot(pose: .asleep, color: ModelFamily(model: c.model).sleeping)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(c.name).lineLimit(1).truncationMode(.tail).layoutPriority(1)
                    if let tag = c.tag {
                        Text("· \(tag)").font(Theme.meta).foregroundStyle(.secondary).lineLimit(1).fixedSize()
                    }
                }
                .font(Theme.row)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                ColdChip(text: cold)
                Text("then").foregroundStyle(.secondary)
                Text("+\(extra)")
                if let pct = c.extraPct {
                    Text("(+\(Fmt.rate(pct))%)").font(Theme.meta).foregroundStyle(.secondary)
                }
            }
            .font(Theme.row)
            .monospacedDigit()
            .lineLimit(1)
            .padding(.leading, Self.indent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .help(c.name + (c.model.isEmpty ? "" : " · \(c.model)") + (c.tag.map { "\n" + tagTip($0) } ?? ""))
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isStaticText)
        .accessibilityLabel("\(c.name)\(c.tag.map { ", " + tagTip($0) } ?? ""), \(cold), then plus \(extra)"
                            + (c.extraPct.map { ", plus \(Fmt.rate($0)) percent" } ?? ""))
    }
}

/// A burning session: its running mascot in its model's colour, its share of the spend drawn behind
/// its name (the same bar as `BarRow`, pink for Fable), the model in its tooltip, and a warning
/// ahead of the name for a runaway.
private struct SessionRow: View {
    /// Where its mascot's stride starts, so the rows don't run in lockstep.
    let phase: Double
    let name: String
    let model: String
    /// When the session last ran, after the name, while another row shares its name.
    let tag: String?
    /// Runs on Fable: its bar is pink, the limit's colour.
    let fable: Bool
    let figure: String
    let detail: String?
    /// 0...1 of the row's width.
    let fraction: Double
    /// Set for a runaway: what the warning says.
    let warning: String?
    /// Whether the list keeps a column for the warning (some row in it has one).
    let warned: Bool

    private static let gap = SessionsSection.Inset.gap

    var body: some View {
        let tint = warning != nil ? Theme.color(.warn) : fable ? Theme.fable : Theme.color(.normal)
        HStack(alignment: .center, spacing: Self.gap) {
            Mascot(pose: .run, color: ModelFamily(model: model).full, scale: SessionsSection.mascotScale, phase: phase)
            if warned {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.color(.warn))
                    .opacity(warning == nil ? 0 : 1)
                    .frame(width: SessionsSection.Inset.warning)
                    .accessibilityHidden(true)
            }
            // The name has the line to itself (the model is in the tooltip); a tag, which tells same-named
            // rows apart, goes under it so a long one ("started Sun 9:32 PM") never squeezes the name.
            VStack(alignment: .leading, spacing: 0) {
                Text(name).lineLimit(1).truncationMode(.tail)
                if let tag {
                    Text(tagTip(tag))
                        .font(Theme.meta).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .layoutPriority(1)
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
        .padding(.leading, SessionsSection.Inset.lead)
        .padding(.trailing, 6)
        .padding(.vertical, 1)
        .background {
            ZStack(alignment: .leading) {
                // A runaway's whole row is tinted, however short its bar.
                if warning != nil {
                    RoundedRectangle(cornerRadius: 4, style: .continuous).fill(tint.opacity(0.07))
                }
                // The bar starts where the mascot ends, so it never sits behind it.
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(tint.opacity(warning == nil ? 0.14 : 0.12))
                        .frame(width: max(4, geo.size.width * min(fraction, 1)))
                }
                .padding(.leading, SessionsSection.Inset.lead + SessionsSection.mascotWidth + 2)
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
        var parts = [name] + (tag.map { [tagTip($0)] } ?? []) + [model, "\(figure) per hour"]
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
