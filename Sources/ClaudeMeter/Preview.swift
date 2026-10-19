import AppKit
import SwiftUI

/// `ClaudeMeter --render out.png [--dark] [--history | --help-page] [--fixture name]`: one synchronous pass over
/// the logs (or a made-up state from `Fixtures`), then the popover or History drawn offscreen to a
/// PNG and the menu bar title printed. For checking the UI without screen-recording access. No
/// timers, notifications, or network.
@MainActor
enum Preview {
    /// False if there was nothing to draw, or the picture could not be written.
    @discardableResult
    static func render(to path: String, dark: Bool, history: Bool = false, help: Bool = false,
                       fixture name: String? = nil) -> Bool {
        _ = NSApplication.shared
        let meter = Meter()
        let content: AnyView
        if help {
            // Fixed text, nothing read; drawn whole rather than scrolled, so all of it can be checked.
            content = AnyView(HelpView(scrolls: false))
        } else if let name {
            // A made-up state: no logs read.
            if history {
                guard let h = Fixtures.history(name) else {
                    print("unknown History fixture \(name); one of: \(Fixtures.history.joined(separator: ", "))")
                    return false
                }
                content = AnyView(HistoryView(meter: meter, fixture: h, scrolls: false))
            } else {
                guard let f = Fixtures.popover(name) else {
                    print("unknown fixture \(name); one of: \(Fixtures.popover.joined(separator: ", "))")
                    return false
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
            content = history ? AnyView(HistoryView(meter: meter, scrolls: false)) : AnyView(PopoverView(meter: meter))
        }
        let host = NSHostingView(rootView: content.background(Color(nsColor: .windowBackgroundColor)))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: history || help ? HelpView.width : 340, height: 900),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        host.setFrameSize(host.fittingSize)
        window.setContentSize(host.fittingSize)
        RunLoop.main.run(until: Date().addingTimeInterval(0.5)) // let SwiftUI lay out and draw

        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            print("could not draw the view")
            return false
        }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            print("could not encode the picture")
            return false
        }
        do {
            try png.write(to: URL(fileURLWithPath: path))
        } catch {
            print("could not write \(path): \(error.localizedDescription)")
            return false
        }
        print("wrote \(path)")
        return true
    }
}
