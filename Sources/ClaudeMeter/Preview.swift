import AppKit
import SwiftUI

/// `ClaudeMeter --render out.png [--dark] [--history] [--fixture name]`: one synchronous pass over
/// the logs (or a made-up state from `Fixtures`), then the popover or History drawn offscreen to a
/// PNG and the menu bar title printed. For checking the UI without screen-recording access. No
/// timers, notifications, or network.
@MainActor
enum Preview {
    static func render(to path: String, dark: Bool, history: Bool = false, fixture name: String? = nil) {
        _ = NSApplication.shared
        let meter = Meter()
        let content: AnyView
        if let name {
            // A made-up state: no logs read.
            if history {
                guard let h = Fixtures.history(name) else {
                    return print("unknown History fixture \(name); one of: \(Fixtures.history.joined(separator: ", "))")
                }
                content = AnyView(HistoryView(meter: meter, fixture: h))
            } else {
                guard let f = Fixtures.popover(name) else {
                    return print("unknown fixture \(name); one of: \(Fixtures.popover.joined(separator: ", "))")
                }
                // The argument domain is never saved, so the real setting is left alone.
                UserDefaults.standard.setVolatileDomain(["weekScope": f.weekScope], forName: UserDefaults.argumentDomain)
                meter.notice = f.notice
                print("menu bar: \(f.snapshot.menuTitle)")
                content = AnyView(PopoverView(meter: meter, fixture: f.snapshot))
            }
        } else {
            meter.loadOnce()
            print("menu bar: \(meter.snapshot.menuTitle)")
            content = history ? AnyView(HistoryView(meter: meter)) : AnyView(PopoverView(meter: meter))
        }
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
