import SwiftUI

/// The dropdown: a header, a module per section, and the footer.
struct PopoverView: View {
    @ObservedObject var meter: Meter
    var openHistory: () -> Void = {}
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
                    }
                }
                if !s.burning.isEmpty || !s.cooling.isEmpty {
                    Module { SessionsSection(s: s) }
                }
                Module { UsageSection(s: s) }
            }

            FooterView(meter: meter, s: s, openHistory: openHistory)
        }
        .padding(.horizontal, Theme.pad)
        .padding(.top, Theme.pad)
        .padding(.bottom, 8) // the footer buttons carry 3pt of their own
        .frame(width: 340)
    }
}

// MARK: - Header

/// The menu bar's ring and the title, and how many sessions are active.
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
            if s.activeCount > 0 {
                ActivePill(count: s.activeCount)
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

/// "6 active" with a green dot, in a capsule.
private struct ActivePill: View {
    let count: Int

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(Color.green).frame(width: 6, height: 6).accessibilityHidden(true)
            Text("\(count) active").monospacedDigit()
        }
        .font(Theme.meta)
        .foregroundStyle(Color.primary.opacity(0.7))
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(Capsule().fill(Color.green.opacity(0.12)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(count) active")
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
