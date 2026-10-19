import AppKit

/// What the status item shows: the ring and the title.
@MainActor
enum MenuBar {
    /// Sets the ring and the title on the status item's button. The app and `--icons` both go
    /// through here, so the preview is the real thing. `scale` is the pixel density the button will
    /// be drawn at, for the preview to say; the app leaves it to the button's own screen.
    /// `width`: the status item's fixed length. The ring's image is widened on its left to fill it, so
    /// ring and title sit at the slot's right edge with the blank space on the left, like the menu bar's
    /// own spacing, instead of the button centring them and moving the ring about as the title changes.
    static func apply(_ s: Snapshot, to button: NSStatusBarButton, scale: CGFloat? = nil, width: CGFloat? = nil) {
        button.attributedTitle = title(s)
        button.setAccessibilityLabel(spoken(s))
        button.imagePosition = .imageLeading
        let center = ringCenter(in: button, scale: scale ?? button.window?.backingScaleFactor ?? 2)
        button.image = ring(s.menuPct, level: s.level, centerY: center)
        if let width {
            let lead = (width - button.fittingSize.width).rounded(.down)
            if lead > 0 { button.image = ring(s.menuPct, level: s.level, centerY: center, lead: lead) }
        }
    }

    /// The widest the status item gets with or without the weekly %, measured on the real button: the
    /// cap form ("~100% · cap 10:49 PM  wk ~100%") is the longest title. The status item takes this
    /// as its fixed length, so the menu bar never re-lays out (which slid icons in and out from behind
    /// the notch). Changes only when the weekly setting does.
    static func fixedWidth(for button: NSStatusBarButton, weekly: Bool) -> CGFloat {
        let wk = weekly ? "  wk ~100%" : ""
        // Morning and evening, since "AM" and "PM" aren't the same width.
        let clocks = [10, 22].map { Fmt.clock(Calendar.current.date(bySettingHour: $0, minute: 49, second: 0, of: Date()) ?? Date()) }
        var widest: CGFloat = 0
        for text in ["Claude", "$99.99 today", "~100% · 4h59m" + wk] + clocks.map({ "~100% · cap " + $0 + wk }) {
            var s = Snapshot()
            s.menuTitle = text
            s.menuPct = 100
            apply(s, to: button)
            widest = max(widest, button.fittingSize.width)
        }
        return ceil(widest)
    }

    /// What VoiceOver says for the status item: the title as shown, said as words ("about 62%,
    /// 1h05m"), not the ring's percent, which stays 0 when there is no 5-hour card.
    static func spoken(_ s: Snapshot) -> String {
        var text = "Claude usage"
        if s.menuTitle != "Claude" { // while loading the title is just the name
            text += ", " + s.menuTitle.replacingOccurrences(of: "~", with: "about ")
                .replacingOccurrences(of: "  wk ", with: ", weekly ")
                .replacingOccurrences(of: " · ", with: ", ")
        }
        switch s.level {
        case .critical: text += ", critical"
        case .warn: text += ", warning"
        case .normal: break
        }
        return text
    }

    // MARK: - Title

    /// The menu bar's own size (13pt), with tabular digits so the title doesn't shimmy as the
    /// minutes tick over.
    private static let titleFont = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)

    /// Orange from the warn level and red from critical, for the title and the ring alike. Nil at
    /// normal, where the menu bar's own tint applies.
    private nonisolated static func tint(_ level: Level) -> NSColor? {
        switch level {
        case .critical: .systemRed
        case .warn: .systemOrange
        case .normal: nil
        }
    }

    /// "~62% · 1h05m", all in one colour: the menu bar sits on whatever wallpaper there is, and
    /// text dimmed to half strength would be hard to read on some. At normal that is the menu
    /// bar's own tint; from warn the whole title takes the level colour, so it is loud.
    /// There is no leading space: the button leaves 2pt after the image and the ring has a 1pt
    /// margin, which puts the first character about 4pt off the ring, close enough that the two
    /// read as one thing.
    static func title(_ s: Snapshot) -> NSAttributedString {
        var attrs: [NSAttributedString.Key: Any] = [.font: titleFont]
        if let tint = tint(s.level) { attrs[.foregroundColor] = tint }
        return NSAttributedString(string: s.menuTitle, attributes: attrs)
    }

    // MARK: - Ring

    private static let imageSize: CGFloat = 16

    /// A progress ring filled to the 5-hour window's %, clockwise from 12 o'clock. A template
    /// image at normal, so the menu bar tints it for light and dark; at warn and critical it takes
    /// the title's colour and stops being one. `centerY` is where its centre goes, in points up
    /// from the image's bottom.
    /// `lead`: blank points added on the image's left.
    static func ring(_ pct: Double, level: Level, centerY: CGFloat, lead: CGFloat = 0) -> NSImage {
        // @Sendable: AppKit may draw it on any thread, and the drawing touches nothing of the app's.
        let image = NSImage(size: NSSize(width: imageSize + lead, height: imageSize), flipped: false) { @Sendable rect in
            drawRing(pct, level: level, centerY: centerY,
                     in: NSRect(x: rect.minX + lead, y: rect.minY, width: rect.width - lead, height: rect.height))
            return true
        }
        image.isTemplate = level == .normal
        let shown = Int(min(max(pct.isFinite ? pct : 0, 0), 999).rounded())
        let said = level == .critical ? ", critical" : level == .warn ? ", warning" : ""
        image.accessibilityDescription = "Claude usage \(shown)%\(said)"
        return image
    }

    /// Where the ring's centre goes in its image to sit level with the digits beside it. The
    /// button centres the image in its height, but sets the title in a rect of its own that rounds
    /// differently as the menu bar's height changes (and stops following it below 24pt), so the
    /// answer is read from the button's cell rather than assumed: the cell centres the font's line
    /// in that rect and the digits stand on its baseline, a cap height tall. The result is snapped
    /// to the pixel grid the ring is drawn on, so its edges stay crisp. The cell only answers once
    /// the button is in a window; without one, or with a rect that makes no sense, the ring goes
    /// half a point above the image's middle, which is level with the digits in a 24pt bar. The
    /// answer is kept where the 14pt ring fits the image, so a surprise can only misalign it.
    private static func ringCenter(in button: NSStatusBarButton, scale: CGFloat) -> CGFloat {
        let bounds = button.bounds
        guard button.window != nil, button.isFlipped, bounds.height >= imageSize,
              let rect = button.cell?.titleRect(forBounds: bounds),
              rect.minY >= 0, rect.maxY <= bounds.height
        else { return imageSize / 2 + 0.5 }
        let font = titleFont
        let line = font.ascender - font.descender + font.leading
        let baseline = rect.minY + (rect.height - line) / 2 + font.ascender // down from the button's top
        let digits = baseline - font.capHeight / 2
        let top = (bounds.height - imageSize) / 2 // where the button puts the image
        let center = imageSize - ((digits * scale).rounded() / scale - top)
        return min(max(center, 7), imageSize - 7)
    }

    /// A ring 14pt across in the 16pt image, its track a quarter of the ink. It is laid out on the
    /// pixel grid of wherever it is drawn, read from the context: edges on whole pixels are crisp
    /// and any others go soft. The stroke is 2.4pt rounded to whole pixels (2.5pt on a Retina
    /// menu bar, 2pt on a plain display).
    ///
    /// The arc's round caps run past its ends by half the line, so the arc is drawn short by that
    /// much at both ends: its tips then sit exactly on the % rather than reading about 7 points
    /// high, and 90% and 95% stay distinguishable from full. Under a few % it is a dot; within a
    /// point of closing, a full ring.
    ///
    /// Called from the image's drawing handler, which AppKit may run on any thread.
    private nonisolated static func drawRing(_ pct: Double, level: Level, centerY: CGFloat, in rect: NSRect) {
        let tint = tint(level)
        let ink = tint ?? .black // a template image only needs its alpha
        let scale = max(1, NSGraphicsContext.current?.cgContext.convertToDeviceSpace(CGSize(width: 1, height: 1)).width ?? 2)
        let line = (2.4 * scale).rounded() / scale
        let radius = 7 - line / 2
        let center = NSPoint(x: rect.midX, y: rect.minY + centerY)
        let circle = NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)

        let track = NSBezierPath(ovalIn: circle)
        track.lineWidth = line
        ink.withAlphaComponent(tint == nil ? 0.25 : 0.3).setStroke()
        track.stroke()

        let used = min(max(pct.isFinite ? pct : 0, 0), 100) / 100
        guard used > 0 else { return }
        ink.setStroke()
        ink.setFill()
        let sweep = 360 * used // degrees, clockwise from the top
        let cap = Double(line / 2 / radius) * 180 / .pi // what one round cap adds at each end
        let open = (360 - sweep) * .pi / 180 * Double(radius) // the track left showing, in points
        if open < 1 {
            let full = NSBezierPath(ovalIn: circle)
            full.lineWidth = line
            full.stroke()
        } else if sweep <= 2 * cap {
            let a = (90 - cap) * .pi / 180
            let dot = NSPoint(x: center.x + radius * CGFloat(cos(a)), y: center.y + radius * CGFloat(sin(a)))
            NSBezierPath(ovalIn: NSRect(x: dot.x - line / 2, y: dot.y - line / 2, width: line, height: line)).fill()
        } else {
            let arc = NSBezierPath()
            arc.appendArc(withCenter: center, radius: radius, startAngle: 90 - cap, endAngle: 90 - sweep + cap,
                          clockwise: true)
            arc.lineWidth = line
            arc.lineCapStyle = .round
            arc.stroke()
        }
    }

    // MARK: - Preview

    /// `--render out.png --icons`: the status item on a light menu bar and a dark one, at 4x. Real
    /// status bar buttons hosted offscreen and filled through `apply`, so spacing, tint and text
    /// are the system's own. At the top, bare rings (the level colours start at 70 and 90, as in
    /// the dropdown): first at the sheet's 4x, then as a Retina display draws them and as a plain
    /// one does, each device pixel enlarged to a block so the edges can be judged. Below, ring and
    /// title for the states the menu bar can show.
    /// False if the sheet could not be drawn or written.
    @discardableResult
    static func renderIcons(to path: String) -> Bool {
        _ = NSApplication.shared
        let rings: [Double] = [0, 3, 25, 50, 75, 90, 95, 100]
        let titles: [(text: String, pct: Double, level: Level)] = [
            ("Claude", 0, .normal), // before the first reading
            ("$0.42 today", 0, .normal), // no window open
            ("8% · 4h52m", 8, .normal),
            ("34% · 2h50m", 34, .normal),
            ("~62% · 1h05m", 62, .normal),
            ("~78% · 1h10m", 78, .warn),
            ("31% · cap 10:49 PM", 31, .warn), // the pace reaches the cap before the reset
            ("~94% · cap 10:49 PM", 94, .critical),
            ("100% · 12m", 100, .critical),
            ("34% · 2h50m  wk 41%", 34, .normal),
            ("~78% · 1h10m  wk ~42%", 78, .warn),
            ("20% · 3h10m  wk 91%", 20, .critical), // the week sets the colour
            ("~94% · cap Wed 12:10 AM  wk ~100%", 94, .critical), // the longest it gets
        ]
        let scale: CGFloat = 4 // sheet pixels per point
        let densities: [(density: CGFloat, label: String)] = [(scale, "ring 4x"), (2, "Retina 2x"), (1, "plain 1x")]
        let margin: CGFloat = 8
        let gutter: CGFloat = 52 // for the labels of those rows
        let barWidth: CGFloat = 300
        let row: CGFloat = 24 // the menu bar's height, give or take
        let rows = CGFloat(densities.count + titles.count)
        let size = NSSize(width: gutter + barWidth * 2 + margin * 2, height: margin * 2 + row * rows)
        let bars: [(origin: CGFloat, color: NSColor, appearance: NSAppearance?)] = [
            (gutter, NSColor(srgbRed: 0.91, green: 0.91, blue: 0.92, alpha: 1), NSAppearance(named: .aqua)),
            (gutter + barWidth + margin, NSColor(srgbRed: 0.16, green: 0.16, blue: 0.17, alpha: 1),
             NSAppearance(named: .darkAqua)),
        ]

        // A button centres its title in its window, not in its own frame, so each status item gets
        // a window of its own, drawn separately and set into the sheet afterwards.
        var placed: [(window: NSWindow, frame: NSRect, density: CGFloat)] = []
        for bar in bars {
            func place(_ s: Snapshot, row index: Int, x: CGFloat, density: CGFloat, ringOnly: Bool = false) -> CGFloat {
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: row),
                                      styleMask: .borderless, backing: .buffered, defer: false)
                window.appearance = bar.appearance
                let swatch = Swatch(frame: NSRect(x: 0, y: 0, width: 400, height: row), color: bar.color)
                window.contentView = swatch
                let button = NSStatusBarButton(frame: swatch.frame)
                swatch.addSubview(button) // in its window before `apply`, which reads the button's layout
                apply(s, to: button, scale: density)
                if ringOnly {
                    button.title = ""
                    button.imagePosition = .imageOnly
                }
                button.sizeToFit()
                let width = ceil(button.fittingSize.width)
                button.frame = NSRect(x: 0, y: 0, width: width, height: row)
                placed.append((window, NSRect(x: bar.origin + x, y: margin + row * (rows - 1 - CGFloat(index)),
                                              width: width, height: row), density))
                return width
            }
            for (index, entry) in densities.enumerated() {
                var x: CGFloat = 4
                for pct in rings {
                    var s = Snapshot()
                    s.menuPct = pct
                    s.level = WindowView(title: "", pct: pct, exact: true).level
                    x += place(s, row: index, x: x, density: entry.density, ringOnly: true) + 3
                }
            }
            for (index, item) in titles.enumerated() {
                var s = Snapshot()
                s.menuTitle = item.text
                s.menuPct = item.pct
                s.level = item.level
                _ = place(s, row: densities.count + index, x: 4, density: scale)
            }
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.3)) // let the buttons lay out and draw

        func bitmap(_ size: NSSize, density: CGFloat) -> NSBitmapImageRep {
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * density),
                                       pixelsHigh: Int(size.height * density), bitsPerSample: 8, samplesPerPixel: 4,
                                       hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                       bytesPerRow: 0, bitsPerPixel: 0)!
            rep.size = size
            return rep
        }
        let sheet = bitmap(size, density: scale)
        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext(bitmapImageRep: sheet)!
        NSGraphicsContext.current = context
        context.imageInterpolation = .none // enlarged pixels stay square
        NSColor(white: 0.62, alpha: 1).setFill()
        NSRect(origin: .zero, size: size).fill()
        for bar in bars {
            bar.color.setFill()
            NSRect(x: bar.origin, y: margin, width: barWidth, height: row * rows).fill()
        }
        let caption: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 7.5),
                                                      .foregroundColor: NSColor(white: 0.1, alpha: 0.85)]
        for (index, entry) in densities.enumerated() {
            let y = margin + row * (rows - 1 - CGFloat(index)) + (row - 9) / 2
            NSString(string: entry.label).draw(at: NSPoint(x: 4, y: y), withAttributes: caption)
        }
        for (window, frame, density) in placed {
            guard let content = window.contentView else { continue }
            let rep = bitmap(frame.size, density: density)
            content.cacheDisplay(in: NSRect(origin: .zero, size: frame.size), to: rep)
            rep.draw(in: frame)
        }
        NSGraphicsContext.restoreGraphicsState()
        guard let png = sheet.representation(using: .png, properties: [:]) else {
            print("could not encode the sheet")
            return false
        }
        do {
            try png.write(to: URL(fileURLWithPath: path))
            print("wrote \(path)")
            return true
        } catch {
            print("could not write \(path): \(error.localizedDescription)")
            return false
        }
    }
}

/// A flat colour, for the preview's menu bars.
private final class Swatch: NSView {
    private let color: NSColor

    init(frame: NSRect, color: NSColor) {
        self.color = color
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        bounds.fill()
    }
}
