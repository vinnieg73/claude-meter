import SwiftUI

/// How the same usage would have gone on each plan, and which plan covers it.
struct PlanFitSection: View {
    let h: History
    @Binding var plan: Plan

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ModuleTitle(symbol: "square.stack.3d.up", title: "Plan fit")
                Spacer(minLength: 8)
                Text("Your plan").font(Theme.row).foregroundStyle(.secondary).accessibilityHidden(true)
                Picker("Your plan", selection: $plan) {
                    ForEach(Plan.allCases) { Text($0.name).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                // At its natural width a segmented control packs its labels edge to edge.
                .frame(width: 192)
            }
            if !h.plans.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(h.plans) { PlanCard(fit: $0, judged: judged) }
                }
            }
            if let verdict {
                VerdictCallout(verdict: verdict)
            }
        }
    }

    /// Whether anything was measured: windows calibrated, or a weekly reading to go by. Without
    /// either, every plan "fits" only because nothing was counted, so no fit is claimed.
    private var judged: Bool { h.calibrated || h.weekNow != nil }

    /// What happened on the current plan, and the smallest plan that would have covered it.
    private var verdict: Verdict? {
        guard let current = h.plans.first(where: \.current) else { return nil }
        // Nothing measured, so every plan "covers" an empty week: say nothing of the sort.
        if !judged { return Verdict(text: "Nothing is measured yet, so no plan can be judged.", tone: .neutral) }
        let tone: Verdict.Tone = current.fits ? .fits : .trouble
        if current.fits {
            let smaller = h.plans.filter { $0.plan.multiplier < current.plan.multiplier && $0.fits }
                .min { $0.plan.multiplier < $1.plan.multiplier }
            if let smaller { return Verdict(text: "\(smaller.plan.name) would have covered this week too.", tone: tone) }
            return Verdict(text: "\(current.plan.name) has covered this week, and this pace stays inside it.", tone: tone)
        }
        var trouble: [String] = []
        if current.capped > 0 { trouble.append("\(current.capped) window\(current.capped == 1 ? "" : "s") capped") }
        if current.weekOver { trouble.append("the weekly limit is already spent") }
        if let out = current.weekRunsOut { trouble.append("the weekly limit runs out \(Fmt.when(out)) at your average pace") }
        var text = "On \(current.plan.name): " + trouble.joined(separator: ", ") + "."
        if let bigger = h.plans.filter({ $0.plan.multiplier > current.plan.multiplier && $0.fits })
            .min(by: { $0.plan.multiplier < $1.plan.multiplier }) {
            text += " \(bigger.plan.name) would have covered it."
        }
        return Verdict(text: text, tone: tone)
    }
}

private extension PlanFit {
    /// Covered the week: never capped, and the weekly limit neither spent nor running out. The
    /// verdict and each card's symbol go by the same rule.
    var fits: Bool { capped == 0 && weekRunsOut == nil && !weekOver }
}

// MARK: - Plan card

/// One plan: its name, whether it covers the week, and the three numbers behind that.
private struct PlanCard: View {
    let fit: PlanFit
    /// False when nothing was measured, so there is no fit to claim.
    let judged: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Text(fit.plan.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                if fit.current { Chip(text: "you", tint: .accentColor).fixedSize() }
                Spacer(minLength: 4)
                if judged {
                    Image(systemName: fit.fits ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(fit.fits ? Color.green : Color.orange)
                        .accessibilityLabel(fit.fits ? "Fits" : "Doesn't fit")
                }
            }
            .padding(.bottom, 2)
            PlanStat(label: "Capped (7 days)", value: capped, warn: fit.capped > 0)
            PlanStat(label: "Busiest window", value: busiest, warn: fit.peak >= 100)
            PlanStat(label: "Weekly limit at your average", value: weekly, warn: fit.weekOver || fit.weekRunsOut != nil)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(fit.current ? Color.accentColor.opacity(0.08) : Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(fit.current ? Color.accentColor.opacity(0.6) : Theme.hairline,
                          lineWidth: fit.current ? 1 : 0.5))
        .accessibilityElement(children: .combine)
    }

    private var capped: StatValue {
        StatValue(number: fit.capped == 0 ? "never" : "\(fit.capped)×")
    }

    private var busiest: StatValue {
        let (number, unit) = StatValue.split(HistoryView.peak(fit.peak))
        return StatValue(number: number, unit: unit)
    }

    private var weekly: StatValue {
        if fit.weekOver { return StatValue(number: "already over") }
        if let out = fit.weekRunsOut { return StatValue(lead: "runs out ", number: Fmt.when(out)) }
        if let atReset = fit.weekAtReset {
            let (number, unit) = StatValue.split(Fmt.pct(atReset))
            return StatValue(lead: "~", number: number, unit: unit, trail: " at reset")
        }
        return StatValue(number: "–", quiet: true)
    }
}

/// A label over its value; the value is orange, and heavier, where it is a problem.
private struct PlanStat: View {
    let label: String
    let value: StatValue
    var warn = false

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(Theme.meta).foregroundStyle(.secondary).lineLimit(1)
            Text(value.styled(warn: warn))
                .lineLimit(1).minimumScaleFactor(0.8)
                .accessibilityLabel(value.spoken)
        }
    }
}

/// A card value with its small print split off so the number leads: the "~" and the unit are
/// smaller, as in the dropdown's big percentages, and "at reset" recedes.
private struct StatValue {
    var lead = ""
    let number: String
    var unit = ""
    var trail = ""
    /// Nothing to show: drawn in the quiet colour.
    var quiet = false

    private static let normal = Font.system(size: 13, weight: .medium, design: .rounded).monospacedDigit()
    private static let strong = Font.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit()
    private static let small = Font.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit()
    private static let smallQuiet = Font.system(size: 11, weight: .medium, design: .rounded).monospacedDigit()

    /// "58%" is ("58", "%"); "100%+" is ("100", "%+").
    static func split(_ text: String) -> (number: String, unit: String) {
        let number = text.prefix { $0.isNumber || $0 == "." || $0 == "-" }
        return (String(number), String(text.dropFirst(number.count)))
    }

    func styled(warn: Bool) -> AttributedString {
        let tint: Color = warn ? Theme.warnText : quiet ? .secondary : .primary
        func piece(_ text: String, _ font: Font, _ color: Color) -> AttributedString {
            var piece = AttributedString(text)
            piece.font = font
            piece.foregroundColor = color
            return piece
        }
        // The "~" steps back; "runs out" is half the message.
        return piece(lead, Self.small, warn ? tint : tint.opacity(0.7))
            + piece(number, warn ? Self.strong : Self.normal, tint)
            + piece(unit, Self.small, tint)
            + piece(trail, Self.smallQuiet, Color.secondary)
    }

    /// As VoiceOver should read it: "about 70% at reset", not "tilde 70%".
    var spoken: String {
        lead.replacingOccurrences(of: "~", with: "about ") + number + unit + trail
    }
}

// MARK: - Verdict

private struct Verdict {
    enum Tone { case fits, trouble, neutral }
    let text: String
    let tone: Tone
}

/// The answer under the cards, in the colour of the current plan's fit.
private struct VerdictCallout: View {
    let verdict: Verdict

    private var tint: Color {
        switch verdict.tone {
        case .fits: .green
        case .trouble: .orange
        case .neutral: .secondary
        }
    }

    private var symbol: String {
        switch verdict.tone {
        case .fits: "checkmark.circle.fill"
        case .trouble: "exclamationmark.circle.fill"
        case .neutral: "lightbulb"
        }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        let neutral = verdict.tone == .neutral
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Image(systemName: symbol).foregroundStyle(tint).accessibilityHidden(true)
            Text(verdict.text).fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(neutral ? Theme.surface : tint.opacity(0.09)))
        .overlay(shape.strokeBorder(neutral ? Theme.hairline : tint.opacity(0.25), lineWidth: 0.5))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Footnote

/// What the History estimates rest on.
struct HistoryFootnote: View {
    let h: History

    var body: some View {
        Text(text)
            .font(Theme.meta).foregroundStyle(.secondary)
            .lineSpacing(1.5)
            .fixedSize(horizontal: false, vertical: true)
            // In line with what the modules hold, not with their edges.
            .padding(.horizontal, 10)
    }

    private var text: String {
        var text = "Estimates use this Mac's Claude Code logs and today's calibration; claude.ai chat and other devices only show up in exact readings. Days spent on other models (Opus 5 before Sep 22, Fable) are priced differently and may read high."
        if let since = h.exactSince { text += " Exact readings logged since \(Fmt.when(since))." }
        text += " Plan fit assumes each plan's limits scale with its multiplier (Pro 1×, Max 5×, Max 20×)."
        return text
    }
}
