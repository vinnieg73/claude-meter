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
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory) // menu bar only, no Dock icon
        app.delegate = delegate
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let meter = Meter()
    private var item: NSStatusItem!
    private let popover = NSPopover()
    private var subscription: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(toggle)
        item.button?.imagePosition = .imageLeading

        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: PopoverView(meter: meter))

        subscription = meter.$snapshot.sink { [weak self] in self?.render($0) }
        meter.start()
    }

    private func render(_ s: Snapshot) {
        guard let button = item.button else { return }
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

    @objc private func toggle() {
        guard let button = item.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            meter.recompute()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            NSApp.activate()
        }
    }
}
