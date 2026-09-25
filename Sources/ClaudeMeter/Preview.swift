import AppKit
import SwiftUI

/// `ClaudeMeter --render out.png [--dark]`: one synchronous pass over the logs, then the
/// popover drawn offscreen to a PNG and the menu bar title printed. For checking the UI
/// without screen-recording access. No timers, notifications, or network.
@MainActor
enum Preview {
    /// `--render out.png --icons`: the menu bar ring at 0, 10, 35, 60, 85 and 100%, at 4x.
    static func icons(to path: String) {
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
            AppDelegate.ring(level).draw(in: NSRect(x: (CGFloat(i) * 24 + 4) * scale, y: 4 * scale,
                                                    width: 16 * scale, height: 16 * scale))
        }
        NSGraphicsContext.restoreGraphicsState()
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    static func render(to path: String, dark: Bool, history: Bool = false) {
        _ = NSApplication.shared
        let meter = Meter()
        meter.loadOnce()
        print("menu bar: \(meter.snapshot.menuTitle)")

        let content = history ? AnyView(HistoryView(meter: meter)) : AnyView(PopoverView(meter: meter))
        let host = NSHostingView(rootView: content.background(Color(nsColor: .windowBackgroundColor)))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: history ? 560 : 340, height: 900),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        host.setFrameSize(host.fittingSize)
        window.setContentSize(host.fittingSize)
        RunLoop.main.run(until: Date().addingTimeInterval(0.5)) // let SwiftUI lay out and draw

        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        print("wrote \(path)")
    }
}
