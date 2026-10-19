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
        let known: Set = ["--render", "--dark", "--history", "--help-page", "--icons", "--fixture", "--status", "--unregister-login", "--replay",
                          "--status-log", "--status-test", "--window-check"]
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
        // The render options without --render would otherwise start the live app.
        let renderOnly: Set = ["--dark", "--history", "--help-page", "--icons", "--fixture"]
        if args.dropFirst().contains(where: { renderOnly.contains($0) }) { misused() }
        if args.contains("--status") { return Status.print() }
        if args.contains("--window-check") { exit(HistoryChrome.check()) }
        if args.contains("--replay") { exit(Replay.run()) }
        if args.contains("--unregister-login") { return Status.unregisterLogin() }

        // Two meters would post every alert twice, probe twice, and overwrite each other's state. One
        // that's quitting (it saves on the way out, for up to 2 seconds) is given 3 to finish, so a quick
        // relaunch doesn't find it still listed and leave no meter at all.
        if let id = Bundle.main.bundleIdentifier {
            func others() -> Bool {
                NSRunningApplication.runningApplications(withBundleIdentifier: id)
                    .contains { $0 != .current && !$0.isTerminated }
            }
            var waited = 0
            while others(), waited < 30 {
                RunLoop.current.run(until: Date().addingTimeInterval(0.1)) // lets the list of running apps refresh
                waited += 1
            }
            if others() { return print("Claude Meter is already running.") }
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
    private let popoverState = PopoverState()
    private var subscriptions: Set<AnyCancellable> = []
    private var historyWindow: NSWindow?
    private var helpWindow: NSWindow?
    private var hotKey: HotKey?
    private var sigterm: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = "ClaudeMeter" // so a ⌘-drag to a new spot sticks across relaunches
        statusItem.button?.target = self
        statusItem.button?.action = #selector(clicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        popover.behavior = .transient
        popover.delegate = self
        let host = NSHostingController(rootView: PopoverRoot(state: popoverState) {
            PopoverView(meter: self.meter, openHistory: { [weak self] in self?.openHistory() },
                        openHelp: { [weak self] in self?.openHelp() })
        })
        host.sizingOptions = .preferredContentSize // the popover follows the content as sections come and go
        popover.contentViewController = host

        meter.$snapshot.sink { [weak self] in self?.render($0) }.store(in: &subscriptions)
        if statusTest {
            Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { guard let self else { return }; self.render(self.meter.snapshot) }
            }
        }
        meter.$hotkeyOn.sink { [weak self] on in
            guard let self else { return }
            let taken = "⌃⌥⌘U is already taken by another app, so the shortcut isn't working."
            self.hotKey = nil // release the old one first, or the new one can't register the same keys
            if on {
                let key = HotKey { [weak self] in self?.toggle() }
                self.hotKey = key
                if !key.registered { return self.meter.hotkeyNotice = taken }
            }
            self.meter.hotkeyNotice = nil
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

    /// What the status item last showed, so a snapshot that changes none of it leaves the button alone.
    private var shown: (title: String, pct: Double, level: Level)?

    private func render(_ s: Snapshot) {
        guard let button = statusItem.button else { return }
        var s = s
        if statusTest { s = Self.testSnapshot() }
        let pct = (s.menuPct * 10).rounded() / 10 // finer than the ring can show
        if let shown, shown.title == s.menuTitle, shown.pct == pct, shown.level == s.level { return }
        MenuBar.apply(s, to: button)
        shown = (s.menuTitle, pct, s.level)
        if statusLog {
            let title = s.menuTitle
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { // once the menu bar has laid it out
                let f = button.window?.frame ?? .zero // in screen coordinates
                print(String(format: "%@  button %.1f  fits %.1f  window x %.1f w %.1f  %@", ISO8601DateFormatter().string(from: Date()),
                             button.frame.width, button.fittingSize.width, f.minX, f.width, title))
                fflush(stdout)
            }
        }
    }

    /// `--status-log`: print the item's button and window width each time it changes (to check it fits
    /// its text). `--status-test`: show the preview's titles in turn instead of the real one.
    private let statusLog = CommandLine.arguments.contains("--status-log")
    private let statusTest = CommandLine.arguments.contains("--status-test")
    private static var testIndex = 0
    private static func testSnapshot() -> Snapshot {
        // The clock as the meter writes it (its locale's spacing), not typed in.
        let am = "cap " + Fmt.clock(Calendar.current.date(bySettingHour: 10, minute: 49, second: 0, of: Date()) ?? Date())
        let cap = "cap " + Fmt.clock(Calendar.current.date(bySettingHour: 22, minute: 49, second: 0, of: Date()) ?? Date())
        let titles: [(String, Double, Level)] = [
            ("Claude", 0, .normal), ("$0.42 today", 0, .normal), ("8% · 4h52m", 8, .normal),
            ("~62% · 1h05m", 62, .normal), ("31% · " + cap, 31, .warn), ("~94% · " + cap, 94, .critical),
            ("100% · 12m", 100, .critical), ("34% · 2h50m  wk 41%", 34, .normal), ("~78% · 1h10m  wk ~42%", 78, .warn), ("~100% · " + cap, 100, .critical),
            ("~100% · " + am + "  wk ~100%", 100, .critical), ("~100% · 4h59m  wk ~100%", 100, .warn),
        ]
        testIndex += 1
        let t = titles[testIndex % titles.count]
        var s = Snapshot()
        s.menuTitle = t.0
        s.menuPct = t.1
        s.level = t.2
        return s
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
            historyWindow = HistoryChrome.makeWindow(title: "Claude Meter · History",
                                                     autosave: HistoryChrome.historyAutosave, delegate: self) {
                HistoryView(meter: meter, scrolls: $0)
            }
        }
        NSApp.unhide(nil)
        NSApp.activate()
        historyWindow?.makeKeyAndOrderFront(nil)
    }

    private func openHelp() {
        popover.performClose(nil)
        if helpWindow == nil {
            helpWindow = HistoryChrome.makeWindow(title: "Claude Meter · Help", autosave: HistoryChrome.helpAutosave,
                                                  preferredHeight: HelpView.height, delegate: self) { HelpView(scrolls: $0) }
        }
        NSApp.unhide(nil)
        NSApp.activate()
        helpWindow?.makeKeyAndOrderFront(nil)
    }

    /// Opened from the shortcut, the meter took the focus from whatever you were in; closing
    /// the dropdown hands it back rather than leaving your keystrokes going nowhere.
    /// The mascots run only while the dropdown is open.
    func popoverWillShow(_ notification: Notification) {
        popoverState.open = true
    }

    func popoverDidClose(_ notification: Notification) {
        popoverState.open = false
        if NSApp.isActive, historyWindow?.isVisible != true, helpWindow?.isVisible != true { NSApp.hide(nil) }
    }

    /// Dropped on close, so its view stops recomputing history every tick.
    func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSWindow) === historyWindow { historyWindow = nil }
        if (notification.object as? NSWindow) === helpWindow { helpWindow = nil }
    }
}
