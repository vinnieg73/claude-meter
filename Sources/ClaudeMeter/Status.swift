import Foundation
import ServiceManagement
import UserNotifications

/// `ClaudeMeter --status`: how the app is set up and what it last knew, for checking from a
/// terminal. Run it from the installed app so login-item and notification state are its own.
enum Status {
    static func print() {
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            Swift.print(await report())
            done.signal()
        }
        done.wait()
    }

    /// For the uninstall script: a login item outlives the app it points at otherwise.
    static func unregisterLogin() {
        do {
            try SMAppService.mainApp.unregister()
            Swift.print("open at login: removed")
        } catch {
            Swift.print("open at login: \(error.localizedDescription)")
        }
    }

    private static func report() async -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        var lines = ["Claude Meter \(version)"]

        switch SMAppService.mainApp.status {
        case .enabled: lines.append("open at login: on")
        case .notRegistered: lines.append("open at login: off")
        case .requiresApproval: lines.append("open at login: waiting for approval (System Settings → General → Login Items)")
        case .notFound: lines.append("open at login: app not found (run this from the installed app)")
        @unknown default: lines.append("open at login: unknown")
        }

        if Bundle.main.bundleIdentifier != nil {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            let state: String
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral: state = "allowed"
            case .denied: state = "denied (System Settings → Notifications → Claude Meter)"
            case .notDetermined: state = "not asked yet"
            @unknown default: state = "unknown"
            }
            lines.append("notifications: \(state)")
        }
        let prefs = UserDefaults.standard
        lines.append("notifications setting: \(prefs.object(forKey: "notifications") as? Bool ?? true ? "on" : "off")")
        lines.append("weekly in title: \(prefs.bool(forKey: "showWeeklyInTitle") ? "on" : "off")")

        lines.append("claude CLI: \(Probe.cliPath ?? "not found")")

        let state = StateStore().state
        if let r = state.lastExact {
            let age = Int(Date().timeIntervalSince(r.at) / 60)
            let windows = [("5h", r.fiveHour), ("week", r.weekly)]
                .compactMap { name, w in w.map { "\(name) \(Fmt.pct($0.pct))" } }
                .joined(separator: ", ")
            lines.append("last exact reading: \(windows) from \(r.source), \(age)m ago")
        } else {
            lines.append("last exact reading: none")
        }
        if let error = state.probeError { lines.append("probe: failing (\(error))") }
        let caps = [("5h", state.calibration.cap5h), ("week", state.calibration.capWeek)]
            .compactMap { name, cap in cap.map { "\(name) \(Fmt.dollars($0))" } }
        lines.append("calibrated caps: " + (caps.isEmpty ? "none yet" : caps.joined(separator: ", ")))
        let checks = state.checks ?? []
        if !checks.isEmpty {
            let typical = checks.suffix(20).map { abs($0.estimated - $0.exact) }.reduce(0, +)
                / Double(min(checks.count, 20))
            lines.append(String(format: "accuracy: ±%.1f pts over the last %d checks", typical, min(checks.count, 20)))
        }
        return lines.joined(separator: "\n")
    }
}
