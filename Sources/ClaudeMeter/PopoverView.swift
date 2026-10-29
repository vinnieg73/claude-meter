import AppKit
import SwiftUI

/// The dropdown: a header, the Usage / Credits tabs, a module per section, and the footer.
struct PopoverView: View {
    @ObservedObject var meter: Meter
    var openHistory: () -> Void = {}
    var openHelp: () -> Void = {}
    var openCredits: () -> Void = {}
    /// The live dropdown: the modules scroll rather than run off the screen. Off for the renders,
    /// which draw everything.
    var capToScreen = false
    /// For `--render --fixture`: shown instead of the meter's own snapshot.
    var fixture: Snapshot? = nil
    /// "usage" or "credits"; kept between openings, like Today / This week.
    @AppStorage("dropdownTab") private var tab = DropdownTabs.usage

    var body: some View {
        let s = fixture ?? meter.snapshot
        VStack(alignment: .leading, spacing: Theme.gap) {
            PopoverHeader(s: s)
            DropdownTabs(tab: $tab, usage: DropdownTabs.usageDetail(s), credits: DropdownTabs.creditsDetail(s))

            // Taller than the screen allows (a backstop: the tallest Usage states, like `critical`, come to
            // about 925 pt), the modules scroll and the header, tabs and footer stay put.
            if capToScreen, let screen = NSScreen.main {
                // The header, footer and padding take about 95 pt, the popover's arrow and a margin the rest.
                let cap = max(300, screen.visibleFrame.height - 130)
                ScrollView(.vertical) { modules(s) }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(maxHeight: cap)
            } else {
                modules(s)
            }

            FooterView(meter: meter, s: s, openHistory: openHistory, openHelp: openHelp, openCredits: openCredits)
        }
        .padding(.horizontal, Theme.pad)
        .padding(.top, Theme.pad)
        .padding(.bottom, 8) // the footer buttons carry 3pt of their own
        .frame(width: 340)
    }

    /// The modules between the tabs and the footer.
    @ViewBuilder private func modules(_ s: Snapshot) -> some View {
        VStack(alignment: .leading, spacing: Theme.gap) {
        if tab == DropdownTabs.credits {
            if let p = s.planCredits {
                Module { UsageCreditsCard(r: p) }
            }
            if let c = s.credits {
                Module { CreditsCard(c: c, edit: openCredits) }
            } else {
                Module { NoCreditsNote(set: openCredits) }
            }
        } else if !s.loaded {
            Module { LoadingNote() }
        } else {
            if let w = s.fiveHour {
                Module {
                    WindowCard(w: w)
                    ExtraOffLine(w: w, credits: s.planCredits)
                }
            } else {
                Module { NoWindowNote(hasReading: s.hasReading) }
            }
            if let w = s.weekly {
                Module {
                    WindowCard(w: w)
                    ExtraOffLine(w: w, credits: s.planCredits)
                    ExtrasRows(extras: s.extras)
                    if let apps = s.weekSurfaces, !w.blind { WeekAppsLine(surfaces: apps) }
                    // Its Other part is the weekly estimate's, which a blind card doesn't show.
                    if let v = s.weekValue, !w.blind {
                        WeekValueLine(v: v, plan: meter.plan, openHistory: openHistory)
                    }
                }
            }
            if let f = s.fable {
                Module { FableCard(f: f) }
            }
            if !s.burning.isEmpty || !s.cooling.isEmpty {
                Module { SessionsSection(s: s) }
            }
            Module { UsageSection(s: s) }
        }
        }
    }
}

// MARK: - Header

/// The menu bar's ring and the title, and the sessions working now.
private struct PopoverHeader: View {
    let s: Snapshot

    var body: some View {
        HStack(spacing: 7) {
            HeaderRing(pct: s.menuPct, tint: ringTint)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(ringLabel)
                .accessibilityHidden(s.fiveHour == nil)
            Text("Claude usage")
                .font(.system(size: 13, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if !s.burning.isEmpty {
                WorkingPill(burning: s.burning)
            }
        }
        .padding(.horizontal, 2)
    }

    /// Like the menu bar title: the ring stays plain until the title turns orange or red.
    private var ringTint: Color {
        switch s.level {
        case .normal: .primary
        case .warn, .critical: Theme.color(s.level)
        }
    }

    private var ringLabel: String {
        if s.fiveHour?.idle == true { return "5-hour window, idle, no window open" }
        return "5-hour window, \(s.fiveHour?.exact == false ? "about " : "")\(Fmt.pct(s.menuPct)) used"
    }
}

/// The menu bar's ring, drawn in SwiftUI: clockwise from 12 o'clock to the 5-hour %.
private struct HeaderRing: View {
    let pct: Double
    let tint: Color
    var size: CGFloat = 15
    var line: CGFloat = 2.3

    var body: some View {
        let used = min(max(pct, 0), 100) / 100
        ZStack {
            Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: line)
            if used > 0 {
                Circle()
                    .inset(by: line / 2)
                    .trim(from: 0, to: used)
                    .stroke(tint, style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .frame(width: size, height: size)
    }
}

/// A running mascot per burning session, in its model's colour (five at most, then "+2"), and
/// "3 working", in a capsule.
private struct WorkingPill: View {
    let burning: [Burn]

    private static let shown = 5

    var body: some View {
        let extra = burning.count - Self.shown
        HStack(spacing: 4) {
            HStack(spacing: 2) {
                ForEach(Array(burning.prefix(Self.shown).enumerated()), id: \.offset) { i, b in
                    Mascot(pose: .run, color: ModelFamily(model: b.model).full, phase: Double(i) * Mascot.stagger)
                }
            }
            if extra > 0 {
                Text("+\(extra)").monospacedDigit()
            }
            Text("\(burning.count) working").monospacedDigit()
        }
        .font(Theme.meta)
        .lineLimit(1)
        .fixedSize()
        .foregroundStyle(.secondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(Capsule().fill(Theme.track))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(burning.count) working")
    }
}

// MARK: - Tabs

/// Usage (the limits, sessions and spend) and Credits (claude.ai usage credits and the Console's API
/// credits), full width under the header. Each says its headline in words: "Usage · 62%", "Credits · $107
/// left", and in red, whichever tab is open, "Credits · out Nov 11" while the API credits card's line is red.
/// Words rather than a dot, which read like a notification that looking clears (v0.9.33).
struct DropdownTabs: View {
    static let usage = "usage"
    static let credits = "credits"

    @Binding var tab: String
    let usage: Detail?
    let credits: Detail?
    @Environment(\.colorScheme) private var scheme

    struct Detail {
        var text: String
        var alarm = false
    }

    /// The 5-hour % the menu bar's ring shows; nothing while idle or signed out.
    static func usageDetail(_ s: Snapshot) -> Detail? {
        guard let w = s.fiveHour, !w.idle, !w.blind else { return nil }
        return Detail(text: (w.exact ? "" : "~") + Fmt.pct(w.pct))
    }

    /// What's left of the API credits, or (red) when they run out before they expire, or are used up.
    static func creditsDetail(_ s: Snapshot) -> Detail? {
        guard let c = s.credits else { return nil }
        if c.expired { return Detail(text: "expired") }
        if c.alarm {
            if c.left <= 0 { return Detail(text: "used up", alarm: true) }
            if let out = c.runsOut { return Detail(text: "out \(ConsoleCredits.day.string(from: out))", alarm: true) }
        }
        return Detail(text: String(format: "$%.0f left", max(0, c.left.rounded(.down))))
    }

    var body: some View {
        HStack(spacing: 2) {
            segment("Usage", Self.usage, usage)
            segment("Credits", Self.credits, credits)
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.track))
    }

    private func segment(_ title: String, _ id: String, _ detail: Detail?) -> some View {
        let on = tab == id
        return Button { tab = id } label: {
            HStack(spacing: 0) {
                Text(title)
                if let detail {
                    Text(" · \(detail.text)")
                        .monospacedDigit()
                        .foregroundStyle(detail.alarm ? Color.red : on ? Color.primary : Color.secondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .font(.system(size: 11, weight: on ? .semibold : .regular))
            .foregroundStyle(on ? Color.primary : Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 3)
            .background {
                if on {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(scheme == .dark ? Color.white.opacity(0.16) : Color.white)
                        .shadow(color: .black.opacity(0.12), radius: 0.5, y: 0.5)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(detail.map { "\(title), \($0.text)" } ?? title)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }
}

/// Under the 5-hour or weekly card from 70% (orange, red from 90%, as the card), when claude.ai extra usage is
/// off: the plan's limit is a hard stop. Where it bites, rather than a marker on the Credits tab.
private struct ExtraOffLine: View {
    let w: WindowView
    let credits: PlanCredits.Reading?

    var body: some View {
        if let c = credits, c.limitReached || c.extraOn == false, !w.blind, !w.idle, w.level != .normal {
            Text(c.limitReached ? "Extra usage hit its monthly limit, so you'll stop at this limit."
                                : "Extra usage is off, so you'll stop at this limit.")
                .font(Theme.meta)
                .foregroundStyle(Theme.text(Theme.color(w.level)))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Under the weekly card: Anthropic's split of the week by app, so chat, Cowork and Claude Duet are seen, not
/// just counted. One gray line; the named apps even at 0%.
private struct WeekAppsLine: View {
    let surfaces: [PlanCredits.Surface]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            Text("Share by app: " + PlanCredits.surfaceText(surfaces, short: true))
            Text(PlanCredits.surfaceText(surfaces, short: true))
        }
        .font(Theme.meta)
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .help("Anthropic's split of this week's usage by app, as claude.ai shows it.")
        .accessibilityLabel("This week by app: " + PlanCredits.surfaceText(surfaces, short: false))
    }
}

/// The Credits tab before a Console balance is typed in.
private struct NoCreditsNote: View {
    let set: () -> Void

    var body: some View {
        NoteRow {
            Image(systemName: "creditcard")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.secondary)
        } words: {
            VStack(alignment: .leading, spacing: 1) {
                Text("API credits").font(Theme.title)
                Text("Type in your balance from the Console to track it.")
                    .font(Theme.meta).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Button("Set up", action: set)
                .controlSize(.small)
        }
    }
}

// MARK: - Loading and empty

/// A placeholder row: a glyph in a fixed column, then the words. The loading and empty modules
/// share it, so their text starts in the same place.
private struct NoteRow<Glyph: View, Words: View>: View {
    @ViewBuilder var glyph: Glyph
    @ViewBuilder var words: Words

    var body: some View {
        HStack(spacing: 10) {
            glyph.frame(width: 20).accessibilityHidden(true)
            words
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The first read of the logs: a quiet placeholder where the first module will be.
private struct LoadingNote: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NoteRow {
            // Under Reduce Motion a still glyph stands in for the spinner.
            if reduceMotion {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.secondary)
            } else {
                ProgressView().controlSize(.small)
            }
        } words: {
            Text("Reading Claude Code logs…").font(Theme.row).foregroundStyle(.secondary)
        }
        .frame(minHeight: 20)
    }
}

/// Where the 5-hour card goes when there is no window to show.
private struct NoWindowNote: View {
    let hasReading: Bool

    private var title: String { hasReading ? "Waiting for a 5-hour reading" : "No limit reading yet" }
    private var hint: String { hasReading ? "One comes with your next message." : "Press Sync to take one." }

    var body: some View {
        NoteRow {
            Image(systemName: hasReading ? "hourglass" : "gauge.with.dots.needle.0percent")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(.secondary)
        } words: {
            // One line when both fit, else the hint under the title.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 6) { titleText; hintText }
                VStack(alignment: .leading, spacing: 0) { titleText; hintText }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var titleText: some View {
        Text(title).font(Theme.title)
    }

    private var hintText: some View {
        Text(hint).font(Theme.meta).foregroundStyle(.secondary)
    }
}
