import SwiftUI

/// The History window: the last week of 5-hour windows, this week's climb against an even pace,
/// and how the same usage would have gone on each plan.
struct HistoryView: View {
    @ObservedObject var meter: Meter
    /// For `--render --fixture`: shown instead of the meter's own history.
    var fixture: History? = nil

    /// Window edge, and the gap between modules: roomier than the dropdown's, for 560pt.
    private static let edge: CGFloat = 16
    private static let gap: CGFloat = 12

    var body: some View {
        let h = fixture ?? meter.history()
        VStack(alignment: .leading, spacing: Self.gap) {
            Module { HistoryWindowsChart(h: h) }
            Module { HistoryWeekChart(h: h) }
            Module { PlanFitSection(h: h, plan: $meter.plan) }
            HistoryFootnote(h: h)
        }
        .padding(Self.edge)
        .frame(width: 560)
    }

    /// Usage stops at the cap, so anything past it is an estimate overshooting; say "100%+".
    static func peak(_ value: Double) -> String { value >= 100 ? "100%+" : Fmt.pct(value) }
}
