import AppKit
import Combine
import SwiftUI

@main
@MainActor
enum Main {
    static let delegate = AppDelegate()

    static let usage = """
        usage: ClaudeMeter                      run the menu bar app
               ClaudeMeter --status             print setup and last known state
               ClaudeMeter --render out.png [--dark] [--history | --icons]
               ClaudeMeter --unregister-login
               ClaudeMeter --replay             replay this Mac's history through the meter and check it
        """

    static func main() {
        let args = CommandLine.arguments
        // A typo shouldn't start a second meter: unknown or incomplete flags print usage.
        let known: Set = ["--render", "--dark", "--history", "--icons", "--status", "--unregister-login", "--replay"]
        if args.dropFirst().contains(where: { $0.hasPrefix("--") && !known.contains($0) }) {
            return print(usage)
        }
        if let i = args.firstIndex(of: "--render") {
            guard i + 1 < args.count, !args[i + 1].hasPrefix("--") else { return print(usage) }
            if args.contains("--icons") { return Preview.icons(to: args[i + 1]) }
            Preview.render(to: args[i + 1], dark: args.contains("--dark"), history: args.contains("--history"))
            return
        }
        if args.contains("--status") { return Status.print() }
        if args.contains("--replay") { exit(Replay.run()) }
        if args.contains("--unregister-login") { return Status.unregisterLogin() }

        // Two meters would post every alert twice, probe twice, and overwrite each other's state.
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: { $0 != .current }) {
            return print("Claude Meter is already running.")
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory) // menu bar only, no Dock icon
        app.delegate = delegate
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSPopoverDelegate {
    private let meter = Meter()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var subscriptions: Set<AnyCancellable> = []
    private var historyWindow: NSWindow?
    private var hotKey: HotKey?
    private var sigterm: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(clicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem.button?.imagePosition = .imageLeading

        popover.behavior = .transient
        popover.delegate = self
        let host = NSHostingController(rootView: PopoverView(meter: meter) { [weak self] in self?.openHistory() })
        host.sizingOptions = .preferredContentSize // the popover follows the content as sections come and go
        popover.contentViewController = host

        meter.$snapshot.sink { [weak self] in self?.render($0) }.store(in: &subscriptions)
        meter.$hotkeyOn.sink { [weak self] on in
            guard let self else { return }
            let taken = "⌃⌥⌘U is already taken by another app, so the shortcut isn't working."
            self.hotKey = nil // release the old one first, or the new one can't register the same keys
            if on {
                let key = HotKey { [weak self] in self?.toggle() }
                self.hotKey = key
                if !key.registered { return self.meter.notice = taken }
            }
            if self.meter.notice == taken { self.meter.notice = nil }
        }.store(in: &subscriptions)
        meter.start()

        // pkill and logout send SIGTERM, which skips applicationWillTerminate; route it there
        // so the log index is saved.
        signal(SIGTERM, SIG_IGN)
        sigterm = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        sigterm?.setEventHandler { NSApp.terminate(nil) }
        sigterm?.resume()
    }

    func applicationWillTerminate(_ notification: Notification) {
        meter.shutdown()
    }

    private func render(_ s: Snapshot) {
        guard let button = statusItem.button else { return }
        button.image = Self.ring(s.menuPct)

        var attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
        ]
        switch s.level {
        case .critical: attrs[.foregroundColor] = NSColor.systemRed
        case .warn: attrs[.foregroundColor] = NSColor.systemOrange
        case .normal: break
        }
        button.attributedTitle = NSAttributedString(string: " " + s.menuTitle, attributes: attrs)
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

    @objc private func clicked() {
        if NSApp.currentEvent?.type == .rightMouseUp { showMenu() } else { toggle() }
    }

    private func toggle() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            meter.refreshNow()
            NSApp.unhide(nil) // closing the dropdown hides the app to hand focus back
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            NSApp.activate()
        }
    }

    private func showMenu() {
        popover.performClose(nil)
        let menu = NSMenu()
        menu.addItem(menuItem("Sync now", #selector(syncNow)))
        menu.addItem(menuItem("History…", #selector(showHistory)))
        menu.addItem(.separator())
        menu.addItem(menuItem("Open at login", #selector(toggleLogin), on: meter.launchAtLogin))
        menu.addItem(menuItem("Weekly % in menu bar", #selector(toggleWeekly), on: meter.showWeeklyInTitle))
        menu.addItem(menuItem("Notifications", #selector(toggleNotifications), on: meter.notificationsOn))
        menu.addItem(menuItem("Send test notification", #selector(testNotification)))
        menu.addItem(menuItem("Shortcut ⌃⌥⌘U", #selector(toggleHotkey), on: meter.hotkeyOn))
        menu.addItem(.separator())
        let version = NSMenuItem(title: "Claude Meter \(Meter.version)", action: nil, keyEquivalent: "")
        version.isEnabled = false
        menu.addItem(version)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Claude Meter", action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        // A status item shows its menu on click only while it has one; attach it for this click.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func menuItem(_ title: String, _ action: Selector, on: Bool? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        if let on { item.state = on ? .on : .off }
        return item
    }

    @objc private func syncNow() { meter.sync(force: true) }
    @objc private func toggleLogin() { meter.setLaunchAtLogin(!meter.launchAtLogin) }
    @objc private func toggleWeekly() { meter.showWeeklyInTitle.toggle() }
    @objc private func toggleNotifications() { meter.notificationsOn.toggle() }
    @objc private func testNotification() { meter.testNotification() }
    @objc private func toggleHotkey() { meter.hotkeyOn.toggle() }
    @objc private func showHistory() { openHistory() }

    private func openHistory() {
        popover.performClose(nil)
        if historyWindow == nil {
            let host = NSHostingController(rootView: HistoryView(meter: meter))
            host.sizingOptions = .preferredContentSize
            let window = NSWindow(contentViewController: host)
            window.title = "Claude Meter · History"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            historyWindow = window
        }
        NSApp.unhide(nil)
        NSApp.activate()
        historyWindow?.makeKeyAndOrderFront(nil)
    }

    /// Opened from the shortcut, the meter took the focus from whatever you were in; closing
    /// the dropdown hands it back rather than leaving your keystrokes going nowhere.
    func popoverDidClose(_ notification: Notification) {
        if NSApp.isActive, historyWindow?.isVisible != true { NSApp.hide(nil) }
    }

    /// Dropped on close, so its view stops recomputing history every tick.
    func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSWindow) === historyWindow { historyWindow = nil }
    }
}
