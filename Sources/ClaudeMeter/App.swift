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
               ClaudeMeter --render out.png [--dark] [--history | --help-page | --icons] [--fixture name]
               ClaudeMeter --unregister-login
               ClaudeMeter --replay             replay this Mac's history through the meter and check it
        """

    static func main() {
        let args = CommandLine.arguments
        // A typo shouldn't start a second meter: unknown or incomplete flags print usage, and fail,
        // so a script that mistyped one doesn't take it for a render that worked.
        func misused() -> Never {
            print(usage)
            exit(2)
        }
        let known: Set = ["--render", "--dark", "--history", "--help-page", "--icons", "--fixture", "--status", "--unregister-login", "--replay"]
        if args.dropFirst().contains(where: { $0.hasPrefix("--") && !known.contains($0) }) { misused() }
        if let i = args.firstIndex(of: "--render") {
            guard i + 1 < args.count, !args[i + 1].hasPrefix("--") else { misused() }
            if args.contains("--icons") { exit(MenuBar.renderIcons(to: args[i + 1]) ? 0 : 1) }
            var fixture: String?
            if let f = args.firstIndex(of: "--fixture") {
                guard f + 1 < args.count, !args[f + 1].hasPrefix("--") else { misused() }
                fixture = args[f + 1]
            }
            // A picture that wasn't drawn or written is a failure: scripts go by the exit code.
            exit(Preview.render(to: args[i + 1], dark: args.contains("--dark"), history: args.contains("--history"),
                                help: args.contains("--help-page"), fixture: fixture) ? 0 : 1)
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
    private var helpWindow: NSWindow?
    private var hotKey: HotKey?
    private var sigterm: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(clicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        popover.behavior = .transient
        popover.delegate = self
        let host = NSHostingController(rootView: PopoverView(meter: meter, openHistory: { [weak self] in self?.openHistory() },
                                                                   openHelp: { [weak self] in self?.openHelp() }))
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
        MenuBar.apply(s, to: button)
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
        meter.refreshLaunchAtLogin()
        let menu = NSMenu()
        // The version heads the menu as a label, not an item that happens to be greyed out.
        menu.addItem(.sectionHeader(title: "Claude Meter \(Meter.version)"))
        // The symbols are all 14 to 17pt wide. The image column is as wide as the widest one, so a
        // wide glyph (a laptop is 22pt) would push every title along.
        menu.addItem(menuItem("Sync now", "arrow.clockwise", #selector(syncNow)))
        menu.addItem(menuItem("History…", "chart.xyaxis.line", #selector(showHistory)))
        menu.addItem(menuItem("Help…", "questionmark.circle", #selector(showHelp)))
        menu.addItem(.separator())
        menu.addItem(menuItem("Open at login", "arrow.up.forward.app", #selector(toggleLogin), on: meter.launchAtLogin))
        menu.addItem(menuItem("Weekly % in menu bar", "calendar", #selector(toggleWeekly), on: meter.showWeeklyInTitle))
        menu.addItem(menuItem("Notifications", "bell", #selector(toggleNotifications), on: meter.notificationsOn))
        menu.addItem(menuItem("Send test notification", "bell.badge", #selector(testNotification)))
        menu.addItem(menuItem("Shortcut ⌃⌥⌘U", "command", #selector(toggleHotkey), on: meter.hotkeyOn))
        menu.addItem(.separator())
        // No target: the quit action goes down the responder chain to the application.
        let quit = NSMenuItem(title: "Quit Claude Meter", action: #selector(NSApplication.terminate(_:)),
                              keyEquivalent: "q")
        setSymbol("power", on: quit)
        menu.addItem(quit)
        // A status item shows its menu on click only while it has one; attach it for this click.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func menuItem(_ title: String, _ symbol: String, _ action: Selector, on: Bool? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        setSymbol(symbol, on: item)
        if let on { item.state = on ? .on : .off }
        return item
    }

    /// A menu item's SF Symbol. Decorative, so it has no description for VoiceOver to read. macOS 27
    /// usually hides item images unless the item asks for them.
    private func setSymbol(_ name: String, on item: NSMenuItem) {
        item.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        if #available(macOS 27.0, *) { item.preferredImageVisibility = .visible }
    }

    @objc private func syncNow() { meter.sync(force: true) }
    @objc private func toggleLogin() { meter.setLaunchAtLogin(!meter.launchAtLogin) }
    @objc private func toggleWeekly() { meter.showWeeklyInTitle.toggle() }
    @objc private func toggleNotifications() { meter.notificationsOn.toggle() }
    @objc private func testNotification() { meter.testNotification() }
    @objc private func toggleHotkey() { meter.hotkeyOn.toggle() }
    @objc private func showHistory() { openHistory() }
    @objc private func showHelp() { openHelp() }

    private func openHistory() {
        popover.performClose(nil)
        if historyWindow == nil {
            historyWindow = HistoryChrome.makeWindow(title: "Claude Meter · History", delegate: self) {
                HistoryView(meter: meter)
            }
        }
        NSApp.unhide(nil)
        NSApp.activate()
        historyWindow?.makeKeyAndOrderFront(nil)
    }

    private func openHelp() {
        popover.performClose(nil)
        if helpWindow == nil {
            helpWindow = HistoryChrome.makeWindow(title: "Claude Meter · Help", delegate: self) { HelpView() }
        }
        NSApp.unhide(nil)
        NSApp.activate()
        helpWindow?.makeKeyAndOrderFront(nil)
    }

    /// Opened from the shortcut, the meter took the focus from whatever you were in; closing
    /// the dropdown hands it back rather than leaving your keystrokes going nowhere.
    func popoverDidClose(_ notification: Notification) {
        if NSApp.isActive, historyWindow?.isVisible != true, helpWindow?.isVisible != true { NSApp.hide(nil) }
    }

    /// Dropped on close, so its view stops recomputing history every tick.
    func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSWindow) === historyWindow { historyWindow = nil }
        if (notification.object as? NSWindow) === helpWindow { helpWindow = nil }
    }
}
