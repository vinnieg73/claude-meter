import SwiftUI

/// The History window: the last week of 5-hour windows, this week's climb against an even pace,
/// and how the same usage would have gone on each plan.
struct HistoryView: View {
    @ObservedObject var meter: Meter
    /// For `--render --fixture`: shown instead of the meter's own history.
    var fixture: History? = nil

    var body: some View {
        let h = fixture ?? meter.history()
        VStack(alignment: .leading, spacing: 12) {
            Module { HistoryWindowsChart(h: h) }
            Module { HistoryWeekChart(h: h) }
            Module { PlanFitSection(h: h, plan: $meter.plan) }
            HistoryFootnote(h: h)
        }
        .padding(16)
        .frame(width: 560)
    }

    /// Usage stops at the cap, so anything past it is an estimate overshooting; say "100%+".
    static func peak(_ value: Double) -> String { value >= 100 ? "100%+" : Fmt.pct(value) }
}
