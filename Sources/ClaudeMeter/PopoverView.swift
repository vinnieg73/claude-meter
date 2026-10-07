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
            header(s)

            if !s.loaded {
                ProgressView("Reading Claude Code logs…").controlSize(.small)
            } else {
                if let w = s.fiveHour {
                    Module { WindowCard(w: w) }
                } else {
                    Module {
                        Text(s.hasReading ? "Waiting for a 5-hour reading; one comes with your next message."
                                          : "No limit reading yet. Press Sync to take one.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
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
        .padding(Theme.pad)
        .frame(width: 340)
    }

    private func header(_ s: Snapshot) -> some View {
        HStack {
            Text("Claude usage").font(.headline)
            Spacer()
            if s.activeCount > 0 {
                HStack(spacing: 4) {
                    Circle().fill(.green).frame(width: 6, height: 6)
                    Text("\(s.activeCount) active").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
