import AppKit
import SwiftUI

/// The shared look of the dropdown and the History window: spacing, type, surfaces, and the few
/// building blocks every section uses.
enum Theme {
    /// Popover edge, and the gap between modules.
    static let pad: CGFloat = 10
    static let gap: CGFloat = 6
    static let radius: CGFloat = 10

    static let hero = Font.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit()
    static let heroUnit = Font.system(size: 13, weight: .semibold, design: .rounded)
    static let title = Font.system(size: 12, weight: .semibold)
    static let row = Font.system(size: 11)
    static let meta = Font.system(size: 10)
    static let chip = Font.system(size: 9.5, weight: .medium)

    /// Module fill, its edge, empty tracks, and bars that aren't the highlighted one.
    static let surface = Color.primary.opacity(0.045)
    static let hairline = Color.primary.opacity(0.07)
    static let track = Color.primary.opacity(0.08)
    static let quiet = Color.primary.opacity(0.16)

    /// Orange for small text, used only where Help shows the menu bar's cap warning. System orange is too
    /// pale to read at 9–11pt on a light surface (about 2:1), so the light appearance gets a deeper shade of
    /// the same hue (about 3.3:1); dark keeps the system colour. Resolved per appearance, so it follows
    /// Increase Contrast like the system colours do.
    static let warnText = Color(nsColor: NSColor(name: nil) { appearance in
        var resolved = NSColor.systemOrange
        appearance.performAsCurrentDrawingAppearance {
            guard appearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua,
                  let c = NSColor.systemOrange.usingColorSpace(.sRGB) else { return }
            resolved = NSColor(hue: c.hueComponent, saturation: min(1, c.saturationComponent + 0.12),
                               brightness: c.brightnessComponent * 0.76, alpha: 1)
        }
        return resolved
    })

    /// Grayscale first: bars, charts and numbers are gray, and colour is kept for 90% and over (red) and for
    /// real alerts. The warn level (70%) is a darker gray, not a colour. The Credits tab is the model.
    static let neutral = Color.secondary

    static func color(_ level: Level) -> Color {
        switch level {
        case .critical: .red
        case .warn: .primary
        case .normal: neutral
        }
    }
}

/// A section of the dropdown or History: a rounded group on the window's surface.
struct Module<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 5) { content }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 0.5))
    }
}

/// A module's title with its symbol.
struct ModuleTitle: View {
    let symbol: String
    let title: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 13)
                .accessibilityHidden(true)
            Text(title).font(Theme.title)
        }
    }
}

/// A short status in a gray capsule: "est. ±1.0 · 3m ago", "3 windows".
struct Chip: View {
    let text: String
    var symbol: String? = nil

    var body: some View {
        HStack(spacing: 3) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 8, weight: .bold)).accessibilityHidden(true)
            }
            Text(text)
        }
        .font(Theme.chip)
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .padding(.horizontal, 5)
        .padding(.vertical, 1.5)
        .background(Capsule().fill(Theme.track))
    }
}

/// A row with its share drawn behind it: projects by spend, sessions by $/hr.
struct BarRow<Leading: View>: View {
    let name: String
    let value: String
    var detail: String? = nil
    /// 0...1 of the row's width; 0 draws no bar.
    let fraction: Double
    var tint: Color = Theme.neutral
    @ViewBuilder var leading: Leading

    var body: some View {
        HStack(spacing: 6) {
            leading
            Text(name).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 4)
            Text(value).monospacedDigit()
            if let detail {
                Text(detail).monospacedDigit().foregroundStyle(.secondary)
                    .frame(width: 54, alignment: .trailing)
            }
        }
        .font(Theme.row)
        .padding(.horizontal, 6)
        .padding(.vertical, 1.5)
        .background(alignment: .leading) {
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(tint.opacity(fraction > 0 ? (tint == Theme.neutral ? 0.16 : 0.18) : 0))
                    .frame(width: max(4, geo.size.width * min(fraction, 1)))
            }
        }
    }
}

extension BarRow where Leading == EmptyView {
    init(name: String, value: String, detail: String? = nil, fraction: Double, tint: Color = Theme.neutral) {
        self.init(name: name, value: value, detail: detail, fraction: fraction, tint: tint) { EmptyView() }
    }
}
