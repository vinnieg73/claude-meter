import AppKit
import SwiftUI

/// The History and Help windows themselves: their chrome, size and placement. Both are 560 pt wide and
/// grow and shrink only in height. They open no taller than their content or the screen (clear of the
/// menu bar and the Dock), and scroll whatever doesn't fit.
@MainActor
enum HistoryChrome {
    static let width: CGFloat = 560
    static let minHeight: CGFloat = 360
    /// Kept clear between the window and the menu bar, the Dock, and the screen's sides.
    static let margin: CGFloat = 8

    /// `content(false)` is the whole page laid out at its natural height, measured for the window's
    /// largest size; `content(true)` scrolls and fills the window. `preferredHeight` caps the first
    /// opening (Help's page is several screens tall). The size the window is dragged to is kept under
    /// `autosave`, and clamped to the screen when it no longer fits. `visible` stands in for the screen
    /// in `--window-check`, which also passes `save: false` so a check never writes the saved size.
    static func makeWindow<Content: View>(title: String, autosave: String, preferredHeight: CGFloat? = nil,
                                          delegate: NSWindowDelegate?, visible: NSRect? = nil, save: Bool = true,
                                          @ViewBuilder content: (Bool) -> Content) -> NSWindow {
        let natural = NSHostingView(rootView: content(false)).fittingSize.height
        let host = NSHostingController(rootView: content(true))
        host.sizingOptions = [] // the window sets the size; the scroll view fills it
        let window = NSWindow(contentViewController: host)
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        // One flat surface: the titlebar shows the window's own background, with no bar or hairline
        // above the modules. The content stays below the titlebar (no full-size content view), so
        // nothing has to be inset for the traffic lights.
        window.backgroundColor = .windowBackgroundColor
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isReleasedWhenClosed = false
        window.delegate = delegate
        window.contentMinSize = NSSize(width: width, height: minHeight)
        window.contentMaxSize = NSSize(width: width, height: max(minHeight, natural.rounded(.up)))
        window.setContentSize(NSSize(width: width, height: max(minHeight, min(natural, preferredHeight ?? natural))))
        window.center()
        // The size it was dragged to last time, if any.
        let restored = window.setFrameUsingName(autosave)
        if save { window.setFrameAutosaveName(autosave) }
        let screen = visible ?? (window.screen ?? NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
        if let screen {
            let tallest = window.frameRect(forContentRect: NSRect(origin: .zero, size: window.contentMaxSize)).height
            var frame = fit(window.frame, tallest: tallest, in: screen)
            // A first opening sits centred on the screen it was clamped to.
            if !restored { frame.origin.y = (screen.midY - frame.height / 2).rounded() }
            window.setFrame(fit(frame, tallest: tallest, in: screen), display: false)
        }
        return window
    }

    /// `frame` no taller than `tallest` or the screen, and wholly on it, inside the margin. A frame
    /// that shrinks keeps its top edge where it was.
    static func fit(_ frame: NSRect, tallest: CGFloat, in visible: NSRect) -> NSRect {
        var f = frame
        let height = min(f.height, tallest, visible.height - 2 * margin)
        f.origin.y += f.height - height
        f.size.height = height
        f.origin.x = max(visible.minX + margin, min(f.minX, visible.maxX - margin - f.width))
        f.origin.y = max(visible.minY + margin, min(f.minY, visible.maxY - margin - f.height))
        return f
    }

    /// `ClaudeMeter --window-check`: builds the History (from the live logs) and Help windows without
    /// showing them, and prints the frame each would open at on this screen and on a 600 pt-tall one.
    static func check() -> Int32 {
        _ = NSApplication.shared
        let meter = Meter()
        meter.loadOnce()
        guard let main = NSScreen.main?.visibleFrame else {
            print("no screen")
            return 1
        }
        let short = NSRect(x: main.minX, y: main.minY, width: main.width, height: 600)
        var ok = true
        for screen in [main, short] {
            print("screen visible \(Int(screen.width))×\(Int(screen.height)) at y \(Int(screen.minY))–\(Int(screen.maxY))")
            let windows = [
                ("History", makeWindow(title: "History", autosave: historyAutosave, delegate: nil, visible: screen, save: false) {
                    HistoryView(meter: meter, scrolls: $0)
                }),
                ("Help", makeWindow(title: "Help", autosave: helpAutosave, preferredHeight: HelpView.height, delegate: nil,
                                    visible: screen, save: false) { HelpView(scrolls: $0) }),
            ]
            for (name, window) in windows {
                let f = window.frame
                let content = window.contentRect(forFrameRect: f)
                let fits = f.minY >= screen.minY && f.maxY <= screen.maxY && f.minX >= screen.minX && f.maxX <= screen.maxX
                ok = ok && fits
                print("  \(name): content max \(Int(window.contentMaxSize.height)) pt, opens \(Int(content.width))×\(Int(content.height)) "
                      + "(window y \(Int(f.minY))–\(Int(f.maxY))) · \(fits ? "fits" : "OFF SCREEN")")
            }
        }
        return ok ? 0 : 1
    }

    static let historyAutosave = "ClaudeMeterHistory"
    static let helpAutosave = "ClaudeMeterHelp"
}
