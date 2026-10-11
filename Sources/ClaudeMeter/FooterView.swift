import SwiftUI

/// Where the numbers come from, any problem to report, and the controls.
struct FooterView: View {
    @ObservedObject var meter: Meter
    let s: Snapshot
    var openHistory: () -> Void = {}
    var openHelp: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let fine = Font.system(size: 9.5)

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            sourcesLine
            ForEach([meter.loginError, meter.notice, meter.hotkeyNotice].compactMap { $0 }, id: \.self) { message in
                line(message, symbol: "exclamationmark.circle.fill", tint: .red)
            }
            buttons
        }
    }

    // MARK: Sources and notices

    @ViewBuilder private var sourcesLine: some View {
        if let failure = s.probeStatus {
            line(Self.splitRetry(failure), symbol: "exclamationmark.triangle.fill", tint: Theme.warnText)
        } else {
            line(sources, symbol: "dot.radiowaves.left.and.right", tint: .secondary)
        }
    }

    /// A small symbol and a sentence that wraps beside it, never under it. The symbol's column
    /// starts where the buttons' pills do, and the header's ring.
    private func line(_ text: String, symbol: String, tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 8.5))
                .frame(width: 13)
                .accessibilityHidden(true)
            Text(text).monospacedDigit()
        }
        .font(Self.fine)
        .foregroundStyle(tint)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.leading, 2)
    }

    /// "Probe failed: ... · retry 11:26 PM" with the retry on its own line instead of after a dot.
    private static func splitRetry(_ failure: String) -> String {
        guard let dot = failure.range(of: " · retr", options: .backwards) else { return failure }
        let retry = failure[failure.index(dot.lowerBound, offsetBy: 3)...]
        return String(failure[..<dot.lowerBound]) + "\n" + retry
    }

    /// The fixed explanation first; what changes (the statusline, calibration) on its own line.
    private var sources: String {
        var status: [String] = []
        if let tap = s.tapSeen { status.append("statusline \(Fmt.ago(tap))") }
        if !s.calibrated { status.append("not calibrated yet") }
        return (["Exact within a minute of activity · ~ = estimated in between"]
                + (status.isEmpty ? [] : [status.joined(separator: " · ")])).joined(separator: "\n")
    }

    // MARK: Controls

    private var buttons: some View {
        HStack(spacing: 2) {
            // While a probe runs the arrow becomes a spinner, or, under Reduce Motion, the label says so.
            Button { meter.sync(force: true) } label: {
                FooterLabel(title: s.probing && reduceMotion ? "Syncing…" : "Sync") {
                    if s.probing && !reduceMotion { ProgressView().controlSize(.mini) } else { Image(systemName: "arrow.clockwise") }
                }
            }
            .buttonStyle(FooterButtonStyle(prominent: true))
            .disabled(s.probing)
            .accessibilityLabel(s.probing ? "Syncing" : "Sync")

            Button { openHistory() } label: {
                FooterLabel(title: "History") { Image(systemName: "chart.xyaxis.line") }
            }
            .buttonStyle(FooterButtonStyle())

            Menu {
                Toggle("Open at login", isOn: Binding(get: { meter.launchAtLogin },
                                                      set: { meter.setLaunchAtLogin($0) }))
                Toggle("Weekly % in menu bar", isOn: $meter.showWeeklyInTitle)
                Toggle("Notifications", isOn: $meter.notificationsOn)
                Button("Send test notification") { meter.testNotification() }
                Toggle("Shortcut ⌃⌥⌘U", isOn: $meter.hotkeyOn)
                Divider()
                Button { openHelp() } label: { Label("Help…", systemImage: "questionmark.circle") }
                Divider()
                Text("Claude Meter \(Meter.version)")
            } label: {
                FooterLabel(title: nil) { Image(systemName: "gearshape") }
            }
            .menuStyle(.button)
            .buttonStyle(FooterButtonStyle())
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Settings")

            Spacer(minLength: 8)

            Button { NSApp.terminate(nil) } label: {
                FooterLabel(title: "Quit") { Image(systemName: "power") }
            }
            .buttonStyle(FooterButtonStyle())
        }
        .padding(.horizontal, 2)
    }
}

/// An icon and a label (or the icon alone) on one line.
private struct FooterLabel<Icon: View>: View {
    let title: String?
    @ViewBuilder var icon: Icon

    var body: some View {
        HStack(spacing: 4) {
            icon
                .font(.system(size: 10.5, weight: .medium))
                .frame(width: 13, height: 13)
                .accessibilityHidden(true)
            if let title { Text(title).font(.system(size: 11, weight: .medium)) }
        }
    }
}

/// Borderless: a soft pill under Sync, the one action, and under the others once the pointer is over them.
private struct FooterButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        Pill(configuration: configuration, prominent: prominent)
    }

    private struct Pill: View {
        let configuration: Configuration
        let prominent: Bool
        @State private var hovering = false
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            let lit = enabled && (hovering || configuration.isPressed)
            configuration.label
                .foregroundStyle(Color.primary.opacity(lit ? 0.95 : enabled ? 0.7 : 0.55))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(lit ? Color.primary.opacity(prominent ? 0.14 : 0.08) : prominent ? Theme.track : .clear))
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .onHover { hovering = $0 }
        }
    }
}
