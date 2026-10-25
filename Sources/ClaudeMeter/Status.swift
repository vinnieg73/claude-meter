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
        if done.wait(timeout: .now() + 10) == .timedOut {
            Swift.print("timed out waiting for macOS (notification settings)")
        }
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

    /// Asked with its own time limit: a macOS that doesn't answer costs this one line, not the report.
    private static func notificationStatus() -> UNAuthorizationStatus? {
        let answered = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var status: UNAuthorizationStatus?
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            status = settings.authorizationStatus
            answered.signal()
        }
        return answered.wait(timeout: .now() + 5) == .success ? status : nil
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
            let state: String
            switch notificationStatus() {
            case nil: state = "no answer from macOS"
            case .authorized, .provisional: state = "allowed"
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
            let age = Int(max(0, Date().timeIntervalSince(r.at)) / 60) // not "-1m" for one stamped a little ahead
            let windows = [("5h", r.fiveHour), ("week", r.weekly)]
                .compactMap { name, w in w.map { "\(name) \(Fmt.pct($0.pct))" } }
                .joined(separator: ", ")
            lines.append("last exact reading: \(windows) from \(r.source), \(age)m ago")
        } else {
            lines.append("last exact reading: none")
        }
        if let f = state.fable {
            let age = Int(max(0, Date().timeIntervalSince(f.at ?? state.fableChecked ?? Date())) / 60)
            var line = "fable limit: \(Fmt.pct(f.pct)) of its week, \(age)m ago"
            if let none = state.fableNone, none > (f.at ?? .distantPast) { line += " (the last report listed no Fable limit)" }
            lines.append(line)
        } else {
            lines.append("fable limit: " + (state.fableNone != nil ? "none on this plan" : "not read yet"))
        }
        if let error = state.probeError { lines.append("probe: failing (\(error))") }
        lines += CloudSessions.statusLines(state: state)
        let caps = [("5h", state.calibration.cap5h), ("week", state.calibration.capWeek)]
            .compactMap { name, cap in cap.map { "\(name) \(Fmt.dollars($0))" } }
        lines.append("calibrated caps: " + (caps.isEmpty ? "none yet" : caps.joined(separator: ", ")))
        for (window, name) in [("5h", "5h"), ("week", "weekly")] {
            let recent = (state.checks ?? []).filter { $0.window == window }.suffix(20)
            guard !recent.isEmpty else { continue }
            let typical = recent.map { abs($0.estimated - $0.exact) }.reduce(0, +) / Double(recent.count)
            lines.append(String(format: "accuracy, %@: ±%.1f pts over the last %d checks", name, typical, recent.count))
        }
        return lines.joined(separator: "\n")
    }
}
