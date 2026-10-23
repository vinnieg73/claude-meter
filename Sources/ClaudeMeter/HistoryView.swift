import SwiftUI

/// The History window: this week's value at pay-as-you-go prices, the last week of 5-hour windows,
/// this week's climb against an even pace, and how the same usage would have gone on each plan.
struct HistoryView: View {
    @ObservedObject var meter: Meter
    /// For `--render --fixture`: shown instead of the meter's own history.
    var fixture: History? = nil
    /// False for `--render` and for measuring: the whole page, not a scroll view.
    var scrolls = true
    /// Told the page's height whenever it changes while it scrolls, so the window can be dragged as tall
    /// as the page has grown (`HistoryChrome.contentHeight`).
    var heightChanged: ((CGFloat) -> Void)? = nil

    /// Window edge, and the gap between modules: roomier than the dropdown's, for 560pt.
    private static let edge: CGFloat = 16
    private static let gap: CGFloat = 12

    var body: some View {
        if scrolls {
            ScrollView(.vertical) {
                page.background {
                    GeometryReader { geo in
                        Color.clear.onChange(of: geo.size.height, initial: true) { _, height in heightChanged?(height) }
                    }
                }
            }
            .frame(width: 560)
        } else {
            page
        }
    }

    private var page: some View {
        let h = fixture ?? meter.history()
        return VStack(alignment: .leading, spacing: Self.gap) {
            Module { WeekValueSection(h: h, plan: meter.plan) }
            Module { HistoryWindowsChart(h: h) }
            Module { HistoryWeekChart(h: h) }
            Module { PlanFitSection(h: h, plan: $meter.plan) }
            HistoryFootnote(h: h, plan: meter.plan)
        }
        .padding(Self.edge)
        .frame(width: 560)
    }

    /// Usage stops at the cap, so anything past it is an estimate overshooting; say "100%+".
    static func peak(_ value: Double) -> String { value >= 100 ? "100%+" : Fmt.pct(value) }
}
