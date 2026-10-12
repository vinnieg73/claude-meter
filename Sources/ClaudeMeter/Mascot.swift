import AppKit
import SwiftUI

/// The Claude Code mascot, the same pixels as the worker band's sprites: 16 units wide and 10 tall,
/// each body row 2 units tall. Drawn in a Canvas at whole points per unit, no image files.
/// Running mascots bob; everything else holds still. They only move while the dropdown is open, and
/// never under Reduce Motion.
struct Mascot: View {
    enum Pose { case run, still, asleep }

    let pose: Pose
    let color: Color
    /// Points per unit: 1 in titles and the header, 2 in the session rows.
    var scale: CGFloat = 1
    /// Seconds into the cycle, so a row of running mascots isn't in lockstep.
    var phase: Double = 0

    @Environment(\.mascotsMove) private var moves
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let width = 16
    static let height = 10
    private static let frame: Double = 0.5

    /// One string per body row ('#' body, '.' empty); each row is 2 units tall. Eye holes are empty,
    /// so the background shows through.
    private static let top = ["..############..", "..##.######.##..", "################", "..############.."]
    private static let legs0 = "...#.#....#.#..."
    private static let legs1 = "..#.#......#.#.."

    /// The pose as a 16 x 10 unit grid, true where the body is.
    private static func grid(stride: Bool, eyesShut: Bool) -> [[Bool]] {
        var g: [[Bool]] = []
        for row in top + [stride ? legs1 : legs0] {
            let cells = row.map { $0 == "#" }
            g.append(cells)
            g.append(cells)
        }
        if eyesShut {
            // Lids down: each eye becomes a 2-unit line along its bottom.
            g[2][4] = true; g[2][11] = true
            g[3][5] = false; g[3][10] = false
        }
        return g
    }

    private static let grids: [String: [[Bool]]] = [
        "run0": grid(stride: false, eyesShut: false),
        "run1": grid(stride: true, eyesShut: false),
        "asleep": grid(stride: false, eyesShut: true),
    ]

    var body: some View {
        // A running mascot keeps a unit of air above it for the bob, so its row never shifts.
        let air: CGFloat = pose == .run ? scale : 0
        Group {
            if pose == .run && moves && !reduceMotion {
                TimelineView(.periodic(from: Date(timeIntervalSinceReferenceDate: phase), by: Self.frame)) { context in
                    let ticks = ((context.date.timeIntervalSinceReferenceDate - phase) / Self.frame).rounded()
                    let stride = Int(ticks).isMultiple(of: 2) == false
                    sprite(stride ? "run1" : "run0", lift: stride ? 0 : scale)
                }
            } else {
                sprite(pose == .asleep ? "asleep" : "run0", lift: 0)
            }
        }
        .frame(width: CGFloat(Self.width) * scale, height: CGFloat(Self.height) * scale + air, alignment: .bottom)
        .accessibilityHidden(true)
    }

    /// One frame, `lift` points up from the bottom of the box (the bob: one whole unit, never less).
    private func sprite(_ name: String, lift: CGFloat) -> some View {
        let g = Self.grids[name] ?? []
        let unit = scale
        return Canvas { ctx, _ in
            // Runs of body along each unit row, all in one path and one fill, so a translucent colour
            // doesn't darken where shapes meet.
            var path = Path()
            for (y, row) in g.enumerated() {
                var x = 0
                while x < row.count {
                    guard row[x] else { x += 1; continue }
                    var end = x
                    while end < row.count && row[end] { end += 1 }
                    path.addRect(CGRect(x: CGFloat(x) * unit, y: CGFloat(y) * unit,
                                        width: CGFloat(end - x) * unit, height: unit))
                    x = end
                }
            }
            ctx.fill(path, with: .color(color))
        }
        .frame(width: CGFloat(Self.width) * unit, height: CGFloat(Self.height) * unit)
        .offset(y: -lift)
    }
}

/// The model a session runs on, by family, and its mascot colours: full while working, muted while
/// resting.
enum ModelFamily: CaseIterable {
    case opus, sonnet, haiku, fable, unknown

    init(model: String) {
        let m = model.lowercased()
        self = m.contains("opus") ? .opus : m.contains("sonnet") ? .sonnet : m.contains("haiku") ? .haiku
            : m.contains("fable") ? .fable : .unknown
    }

    /// "Opus", or nil for a model the meter doesn't know.
    var name: String? {
        switch self {
        case .opus: "Opus"
        case .sonnet: "Sonnet"
        case .haiku: "Haiku"
        case .fable: "Fable"
        case .unknown: nil
        }
    }

    var full: Color { Self.hex(fullHex) }
    var muted: Color { Self.hex(mutedHex) }

    /// Going cold's sleeping mascot: the muted colour lifted a little toward the full one, so its
    /// shut eyes still read at 1 point a unit on a dark surface. Still clearly dimmer than a runner.
    var sleeping: Color { Self.mix(muted: self, 0.3) }

    private static func mix(muted f: ModelFamily, _ t: Double) -> Color {
        let (m, x) = (f.mutedHex, f.fullHex)
        func ch(_ v: Int, _ shift: Int) -> Double { Double((v >> shift) & 0xff) / 255 }
        return Color(.sRGB, red: ch(m, 16) * (1 - t) + ch(x, 16) * t, green: ch(m, 8) * (1 - t) + ch(x, 8) * t,
                     blue: ch(m, 0) * (1 - t) + ch(x, 0) * t)
    }

    private var fullHex: Int {
        switch self {
        case .opus: 0xa78bfa
        case .sonnet: 0xf08a2a
        case .haiku: 0x2dd4bf
        case .fable: 0xf472b6
        case .unknown: 0xe9c944
        }
    }

    private var mutedHex: Int {
        switch self {
        case .opus: 0x5a4f80
        case .sonnet: 0x794c27
        case .haiku: 0x25645b
        case .fable: 0x7c425f
        case .unknown: 0x655721
        }
    }

    private static func hex(_ v: Int) -> Color {
        Color(.sRGB, red: Double((v >> 16) & 0xff) / 255, green: Double((v >> 8) & 0xff) / 255,
              blue: Double(v & 0xff) / 255)
    }
}

extension Mascot {
    /// How far apart running mascots in a row start their cycles.
    static let stagger = 0.33
    /// The gray of a still mascot that stands for no model in particular.
    static let gray = Color(nsColor: .secondaryLabelColor)
}

private struct MascotsMoveKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True while the dropdown is open: the only time running mascots move. Off for Help and renders.
    var mascotsMove: Bool {
        get { self[MascotsMoveKey.self] }
        set { self[MascotsMoveKey.self] = newValue }
    }
}

/// Whether the dropdown is open, for `mascotsMove`. Set by the app delegate as it shows and closes.
@MainActor
final class PopoverState: ObservableObject {
    @Published var open = false
}

/// The dropdown's root: lets its mascots move while it is open.
struct PopoverRoot<Content: View>: View {
    @ObservedObject var state: PopoverState
    @ViewBuilder var content: Content

    var body: some View {
        content.environment(\.mascotsMove, state.open)
    }
}

/// A module title led by still mascots in place of a symbol: one gray for the 5-hour window, the
/// three muted families for the weekly limit, a model's own colour for its weekly limit.
struct MascotTitle: View {
    let colors: [Color]
    let title: String

    var body: some View {
        HStack(spacing: 5) {
            HStack(spacing: 2) {
                ForEach(colors.indices, id: \.self) { Mascot(pose: .still, color: colors[$0]) }
            }
            Text(title).font(Theme.title)
        }
    }

    /// The mascots a limit card wears, by its title.
    static func colors(for title: String) -> [Color] {
        if title == Meter.weeklyTitle { return [ModelFamily.opus, .sonnet, .haiku].map(\.muted) }
        if title.hasPrefix("Weekly") { return [ModelFamily(model: title).full] }
        return [Mascot.gray]
    }
}
