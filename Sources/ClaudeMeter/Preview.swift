import AppKit
import SwiftUI

/// `ClaudeMeter --render out.png [--dark]`: one synchronous pass over the logs, then the
/// popover drawn offscreen to a PNG and the menu bar title printed. For checking the UI
/// without screen-recording access. No timers, notifications, or network.
@MainActor
enum Preview {
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
