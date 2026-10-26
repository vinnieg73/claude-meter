import SwiftUI

/// The dropdown: a header, a module per section, and the footer.
struct PopoverView: View {
    @ObservedObject var meter: Meter
    var openHistory: () -> Void = {}
    var openHelp: () -> Void = {}
    /// For `--render --fixture`: shown instead of the meter's own snapshot.
    var fixture: Snapshot? = nil

    var body: some View {
        let s = fixture ?? meter.snapshot
        VStack(alignment: .leading, spacing: Theme.gap) {
            PopoverHeader(s: s)

            if !s.loaded {
                Module { LoadingNote() }
            } else {
                if let w = s.fiveHour {
                    Module { WindowCard(w: w) }
                } else {
                    Module { NoWindowNote(hasReading: s.hasReading) }
                }
                if let w = s.weekly {
                    Module {
                        WindowCard(w: w)
                        ExtrasRows(extras: s.extras)
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

            FooterView(meter: meter, s: s, openHistory: openHistory, openHelp: openHelp)
        }
        .padding(.horizontal, Theme.pad)
        .padding(.top, Theme.pad)
        .padding(.bottom, 8) // the footer buttons carry 3pt of their own
        .frame(width: 340)
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
