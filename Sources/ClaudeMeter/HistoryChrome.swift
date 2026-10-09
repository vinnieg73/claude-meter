import AppKit
import SwiftUI

/// The History and Help windows themselves: their chrome, size and placement.
@MainActor
enum HistoryChrome {
    static func makeWindow<Content: View>(title: String, delegate: NSWindowDelegate,
                                          @ViewBuilder content: () -> Content) -> NSWindow {
        let host = NSHostingController(rootView: content())
        host.sizingOptions = .preferredContentSize
        let window = NSWindow(contentViewController: host)
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable]
        // One flat surface: the titlebar shows the window's own background, with no bar or hairline
        // above the modules. The content stays below the titlebar (no full-size content view), so
        // nothing has to be inset for the traffic lights and the window sizes from the content as before.
        window.backgroundColor = .windowBackgroundColor
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isReleasedWhenClosed = false
        window.delegate = delegate
        window.center()
        return window
    }
}
