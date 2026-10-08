import AppKit
import SwiftUI

/// A limit window: its %, the chart or bar, when it resets, and where the pace takes it.
struct WindowCard: View {
    let w: WindowView

    private var color: Color { Theme.color(w.level) }

    /// The clock for the 5-hour window, the calendar for the weekly one.
    private var symbol: String { w.title.hasPrefix("Weekly") ? "calendar" : "clock" }

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
            titleRow

            if w.series.count > 1, w.start != nil {
                PaceChart(w: w, color: color)
            } else {
                WindowBar(pct: w.pct, projected: w.averageAtReset ?? w.atReset, color: color,
                          projectedColor: w.projectionWarn && w.level == .normal ? .orange : color)
                    // The chart carries its own air above its plot; the bar gets it here.
                    .padding(.top, 2)
                    .accessibilityHidden(w.idle) // the title row already says it is idle
            }

            if w.idle || w.resetsAt != nil || status != nil { resetLine }

            if w.projection != nil || w.budget != nil {
                VStack(alignment: .leading, spacing: 0) {
                    if let p = w.projection { metaLine(p, warn: w.projectionWarn) }
                    if let b = w.budget { metaLine(b, warn: w.budgetWarn) }
                }
                .font(Theme.meta)
                .monospacedDigit()
            }
        }
    }

    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            ModuleTitle(symbol: symbol, title: w.title)
                .lineLimit(1)
                // The stack reports its symbol's baseline first; sit the title text on the hero's.
                .alignmentGuide(.firstTextBaseline) { $0[.lastTextBaseline] }
            Spacer(minLength: 0)
            // Nothing is open while idle, so its 0% stays quiet rather than taking the level colour.
            WindowHero(pct: w.pct, exact: w.exact, color: w.idle ? Color.secondary : color)
        }
        // The hero's line box carries more air than its digits need; trimmed, the digits sit about as
        // far from the module's top edge as the title does from its left.
        .frame(height: 18)
        // A point of air under the baseline, so the chart's cap line doesn't crowd the hero.
        .padding(.bottom, 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(w.title)
        .accessibilityValue(WindowHero.spoken(pct: w.pct, exact: w.exact, idle: w.idle))
    }

    /// When it resets with a secondary countdown, or the idle note; the status chip at the end.
    /// A chip too long to share the line (a date that far out, a reading from days ago) drops under it.
    private var resetLine: some View {
        let lead = HStack(spacing: w.idle ? 3 : 6) {
            if w.idle {
                Text("Idle.")
                Text("Next message opens a window.").foregroundStyle(.secondary)
            } else if let r = w.resetsAt {
                Text("Resets \(Fmt.when(r))")
                Text("in \(Fmt.duration(r.timeIntervalSinceNow))").foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)

        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                lead
                Spacer(minLength: 8)
                chip
            }
            VStack(alignment: .leading, spacing: 3) {
                lead
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    chip
                }
            }
        }
        .font(Theme.row)
        .monospacedDigit()
        // The chip is taller than the text; a point more keeps it off the bar or chart above.
        .padding(.top, 1)
    }

    /// "exact · 2m ago" / "est. ±1.0 · 3m ago" in a capsule; the tooltip says what the estimate rests on.
    @ViewBuilder private var chip: some View {
        if let status { Chip(text: status).fixedSize().help(tooltip) }
    }

    /// A projection or budget line: secondary, or orange (and a touch heavier, to hold its own) when warned.
    @ViewBuilder private func metaLine(_ text: String, warn: Bool) -> some View {
        if warn {
            Text(text).fontWeight(.medium).foregroundStyle(Theme.warnText)
        } else {
            Text(text).foregroundStyle(Color.secondary)
        }
    }
}

/// The window's % as the card's hero number: a smaller `%`, and a dimmed `~` while it is estimated.
private struct WindowHero: View {
    let pct: Double
    let exact: Bool
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The same rounding as everywhere else, minus the `%` that gets its own, smaller, type.
    private var digits: String { String(Fmt.pct(pct).dropLast()) }

    static func spoken(pct: Double, exact: Bool, idle: Bool) -> String {
        if idle { return "idle, no window open" } // the screen says so; "about 0 percent" would not
        return (exact ? "" : "about ") + "\(Fmt.pct(pct).dropLast()) percent"
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            if !exact { Text("~").font(Theme.heroUnit).opacity(0.65) }
            Text(digits).font(Theme.hero)
                .contentTransition(.numericText(value: pct))
            Text("%").font(Theme.heroUnit)
        }
        .foregroundStyle(color)
        .lineLimit(1)
        .fixedSize()
        // The `%` glyph carries about 1.5pt of side bearing; pull it out so its ink ends where the bar
        // and the chip below end.
        .padding(.trailing, -1.5)
        .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: pct)
    }
}

/// The plain bar: a 6pt capsule filled to the current %, with the pace's landing % ghosted past it
/// when that is higher.
private struct WindowBar: View {
    let pct: Double
    /// Where the pace lands at the reset, if known.
    let projected: Double?
    let color: Color
    let projectedColor: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let height: CGFloat = 6

    private var used: Double { min(max(pct, 0), 100) / 100 }
    private var ghost: Double? {
        guard let projected, projected > pct + 0.5 else { return nil }
        return min(projected, 100) / 100
    }

    /// A capsule is never narrower than it is tall, so 1% still reads as a fill; anything the hero
    /// would round down to 0% stays empty, so the bar and the number agree.
    private func width(of fraction: Double, in total: CGFloat) -> CGFloat {
        fraction >= 0.005 ? max(Self.height, total * fraction) : 0
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                if let ghost {
                    Capsule().fill(projectedColor.opacity(0.22))
                        .frame(width: width(of: ghost, in: geo.size.width))
                }
                if used >= 0.005 {
                    Capsule()
                        .fill(LinearGradient(colors: [color.opacity(0.8), color], startPoint: .leading, endPoint: .trailing))
                        .frame(width: width(of: used, in: geo.size.width))
                }
            }
        }
        .frame(height: Self.height)
        .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: pct)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Usage")
        .accessibilityValue(spoken)
    }

    private var spoken: String {
        var text = "\(Fmt.pct(pct).dropLast()) percent"
        if let projected, ghost != nil { text += ", on pace for \(Fmt.pct(projected).dropLast()) percent at the reset" }
        return text
    }
}

/// Per-model weekly buckets from the last exact reading, under the weekly card.
struct ExtrasRows: View {
    let extras: [WindowView]

    var body: some View {
        if !extras.isEmpty {
            VStack(spacing: 2) {
                ForEach(extras, id: \.title) { x in
                    // Carried over from an older reading: say how old.
                    let age = x.asOf.map { Date().timeIntervalSince($0) } ?? 0
                    HStack(spacing: 6) {
                        Text(x.title).lineLimit(1).truncationMode(.tail)
                        Spacer(minLength: 4)
                        if age > 3600, let asOf = x.asOf {
                            Text("as of \(Fmt.ago(asOf))").lineLimit(1).fixedSize()
                        }
                        Text(Fmt.pct(x.pct))
                            .foregroundStyle(.primary)
                            .frame(minWidth: 30, alignment: .trailing)
                            .fixedSize()
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .font(Theme.meta)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .padding(.top, 5)
            .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 0.5) }
        }
    }
}
