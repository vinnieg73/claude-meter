import SwiftUI

/// Where the numbers come from, any problem to report, and the controls.
struct FooterView: View {
    @ObservedObject var meter: Meter
    let s: Snapshot
    var openHistory: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(sources)
                .font(.caption2).foregroundStyle(s.probeStatus == nil ? .secondary : Color.orange)
                .fixedSize(horizontal: false, vertical: true)
            ForEach([meter.loginError, meter.notice].compactMap { $0 }, id: \.self) { message in
                Text(message).font(.caption2).foregroundStyle(.red)
            }
            HStack {
                Button(s.probing ? "Syncing…" : "Sync") { meter.sync(force: true) }
                    .disabled(s.probing)
                Button("History") { openHistory() }
                Menu {
                    Toggle("Open at login", isOn: Binding(get: { meter.launchAtLogin },
                                                          set: { meter.setLaunchAtLogin($0) }))
                    Toggle("Weekly % in menu bar", isOn: $meter.showWeeklyInTitle)
                    Toggle("Notifications", isOn: $meter.notificationsOn)
                    Button("Send test notification") { meter.testNotification() }
                    Toggle("Shortcut ⌃⌥⌘U", isOn: $meter.hotkeyOn)
                    Divider()
                    Text("Claude Meter \(Meter.version)")
                } label: {
                    Image(systemName: "gearshape")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .controlSize(.small)
        }
    }

    private var sources: String {
        if let failure = s.probeStatus { return failure }
        var parts = ["Exact every 15 min while you work", "~ = estimated in between"]
        if let tap = s.tapSeen { parts.append("statusline \(Fmt.ago(tap))") }
        if !s.calibrated { parts.append("not calibrated yet") }
        return parts.joined(separator: " · ")
    }
}
