import AppKit

/// What the status item shows: the ring and the title.
@MainActor
enum MenuBar {
    static func title(_ s: Snapshot) -> NSAttributedString {
        var attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
        ]
        switch s.level {
        case .critical: attrs[.foregroundColor] = NSColor.systemRed
        case .warn: attrs[.foregroundColor] = NSColor.systemOrange
        case .normal: break
        }
        return NSAttributedString(string: " " + s.menuTitle, attributes: attrs)
    }

    /// A progress ring filled to the 5-hour window's %, clockwise from 12 o'clock. A template
    /// image, so the menu bar tints it for light and dark.
    static func ring(_ pct: Double) -> NSImage {
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            let center = NSPoint(x: rect.midX, y: rect.midY)
            let radius = rect.width / 2 - 2
            let track = NSBezierPath()
            track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
            track.lineWidth = 2.2
            NSColor.black.withAlphaComponent(0.3).setStroke()
            track.stroke()
            let used = min(max(pct, 0), 100) / 100
            if used > 0 {
                let arc = NSBezierPath()
                arc.appendArc(withCenter: center, radius: radius, startAngle: 90,
                              endAngle: 90 - 360 * used, clockwise: true)
                arc.lineWidth = 2.2
                arc.lineCapStyle = .round
                NSColor.black.setStroke()
                arc.stroke()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Claude usage \(Int(pct.rounded()))%"
        return image
    }

    /// `--render out.png --icons`: the ring at 0, 10, 35, 60, 85 and 100%, at 4x.
    static func renderIcons(to path: String) {
        let levels: [Double] = [0, 10, 35, 60, 85, 100]
        let scale: CGFloat = 4
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(CGFloat(levels.count) * 24 * scale),
                                   pixelsHigh: Int(24 * scale), bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: rep.pixelsWide, height: rep.pixelsHigh).fill()
        for (i, level) in levels.enumerated() {
            ring(level).draw(in: NSRect(x: (CGFloat(i) * 24 + 4) * scale, y: 4 * scale,
                                        width: 16 * scale, height: 16 * scale))
        }
        NSGraphicsContext.restoreGraphicsState()
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        print("wrote \(path)")
    }
}
