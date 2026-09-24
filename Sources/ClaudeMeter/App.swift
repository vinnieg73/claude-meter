import AppKit
import Combine
import SwiftUI

@main
@MainActor
enum Main {
    static let delegate = AppDelegate()

    static func main() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--render"), i + 1 < args.count {
            Preview.render(to: args[i + 1], dark: args.contains("--dark"))
            return
        }
        if args.contains("--status") { return Status.print() }
        if args.contains("--unregister-login") { return Status.unregisterLogin() }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory) // menu bar only, no Dock icon
        app.delegate = delegate
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let meter = Meter()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var subscription: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(clicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem.button?.imagePosition = .imageLeading

        popover.behavior = .transient
        let host = NSHostingController(rootView: PopoverView(meter: meter))
        host.sizingOptions = .preferredContentSize // the popover follows the content as sections come and go
        popover.contentViewController = host

        subscription = meter.$snapshot.sink { [weak self] in self?.render($0) }
        meter.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        meter.shutdown()
    }

    private func render(_ s: Snapshot) {
        guard let button = statusItem.button else { return }
        let symbol: String
        switch s.menuPct {
        case ..<20: symbol = "gauge.with.dots.needle.0percent"
        case ..<42: symbol = "gauge.with.dots.needle.33percent"
        case ..<58: symbol = "gauge.with.dots.needle.50percent"
        case ..<85: symbol = "gauge.with.dots.needle.67percent"
        default: symbol = "gauge.with.dots.needle.100percent"
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Claude usage")
        image?.isTemplate = true
        button.image = image

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

    @objc private func clicked() {
        if NSApp.currentEvent?.type == .rightMouseUp { showMenu() } else { toggle() }
    }

    private func toggle() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            meter.refreshNow()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            NSApp.activate()
        }
    }

    private func showMenu() {
        popover.performClose(nil)
        let menu = NSMenu()
        menu.addItem(menuItem("Sync now", #selector(syncNow)))
        menu.addItem(.separator())
        menu.addItem(menuItem("Open at login", #selector(toggleLogin), on: meter.launchAtLogin))
        menu.addItem(menuItem("Weekly % in menu bar", #selector(toggleWeekly), on: meter.showWeeklyInTitle))
        menu.addItem(menuItem("Notifications", #selector(toggleNotifications), on: meter.notificationsOn))
        menu.addItem(menuItem("Send test notification", #selector(testNotification)))
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
}
