import AppKit
import SwiftUI

/// The History window itself: its chrome, size and placement.
@MainActor
enum HistoryChrome {
    static func makeWindow(meter: Meter, delegate: NSWindowDelegate) -> NSWindow {
        let host = NSHostingController(rootView: HistoryView(meter: meter))
        host.sizingOptions = .preferredContentSize
        let window = NSWindow(contentViewController: host)
        window.title = "Claude Meter · History"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.delegate = delegate
        window.center()
        return window
    }
}
