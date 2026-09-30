import Foundation
@preconcurrency import UserNotifications

/// Posts once per window per threshold, and once when a hot 5-hour window resets.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private let store: StateStore
    private let center: UNUserNotificationCenter?
    private let thresholds: [Double] = [80, 95]
    private var currentReset: Date?
    private var peak = 0.0
    /// Whether macOS lets this app notify, refreshed once a minute. Nothing is posted, or
    /// counted as sent, until it does, so an alert due while the permission prompt is still
    /// up goes out once it's answered.
    private(set) var authorized = false
    private var authorizationCheckedAt = Date.distantPast
    /// Alerts handed to macOS but not yet confirmed, so the next tick doesn't send them again.
    private var pending: Set<String> = []

    init(store: StateStore) {
        self.store = store
        // UNUserNotificationCenter traps outside an app bundle (e.g. `swift run`).
        center = Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
        super.init()
        center?.delegate = self
        center?.requestAuthorization(options: [.alert, .sound]) { [weak self] _, _ in
            Task { @MainActor in self?.refreshAuthorization(force: true) }
        }
    }

    /// Without this, macOS drops alerts that arrive while the app is frontmost: whenever the
    /// dropdown or the History window has the focus.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler:
                                            @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated private static func allows(_ status: UNAuthorizationStatus) -> Bool {
        status == .authorized || status == .provisional
    }

    private func refreshAuthorization(force: Bool = false) {
        guard let center, force || Date().timeIntervalSince(authorizationCheckedAt) > 60 else { return }
        authorizationCheckedAt = Date()
        center.getNotificationSettings { [weak self] settings in
            let allowed = Self.allows(settings.authorizationStatus)
            Task { @MainActor in self?.authorized = allowed }
        }
    }

    /// Follows the 5-hour window every time, so switching alerts back on doesn't announce a
    /// reset from hours ago; posts only when `post` (the Notifications setting) is on.
    func check(_ s: Snapshot, now: Date, post: Bool) {
        guard center != nil, s.loaded else { return }
        refreshAuthorization()
        let send = post && authorized

        if let f = s.fiveHour, let resets = f.resetsAt {
            if !Window.same(resets, currentReset) {
                if send, let previous = currentReset, now >= previous, peak >= thresholds[0] {
                    deliver(title: "Claude 5-hour window reset", body: "You're back to a full window.")
                }
                currentReset = resets
                peak = f.pct
            } else {
                peak = max(peak, f.pct)
            }
        } else {
            currentReset = nil
            peak = 0
        }
        guard send else { return }

        for w in [s.fiveHour, s.weekly].compactMap({ $0 }) where !w.idle {
            guard let resets = w.resetsAt else { continue }
            for t in thresholds where w.pct >= t {
                once(w.title, resets, "\(Int(t))",
                     title: "Claude \(w.title.lowercased()) at \(Fmt.pct(w.pct))",
                     body: "Resets \(Fmt.when(resets)), in \(Fmt.duration(resets.timeIntervalSince(now))).")
            }
        }

        // When the current pace (not a held warning) says the cap is half an hour out or less.
        if let f = s.fiveHour, let capAt = f.capAt, s.capWarning != nil, let resets = f.resetsAt {
            let lead = capAt.timeIntervalSince(now)
            if lead > 0, lead <= 1800 {
                once("pace", resets, "0",
                     title: "Claude 5-hour cap in ~\(Fmt.duration(lead))",
                     body: "At this pace you hit it at \(Fmt.when(capAt)). The window resets \(Fmt.when(resets)).")
            }
        }

        // A session eating the window fast enough to look like a loop: once per session per window.
        if let resets = s.fiveHour?.resetsAt {
            for r in s.runaways {
                once("runaway:\(r.id)", resets, "0",
                     title: "\(r.name) is burning fast",
                     body: "It used \(Fmt.pct(r.pct)) of your 5-hour window in the last 30 minutes.")
            }
        }
    }

    /// Sends an alert unless it already went out for this window (allowing for the seconds to
    /// minutes a window's reset time varies by between readings), and records it as sent only
    /// once macOS has taken it.
    private func once(_ kind: String, _ resets: Date, _ detail: String, title: String, body: String) {
        let key = "\(kind)|\(Int(resets.timeIntervalSince1970))|\(detail)"
        let sent = store.state.notified.contains { stored in
            let parts = stored.split(separator: "|")
            guard parts.count == 3, parts[0] == kind, parts[2] == detail, let epoch = Double(parts[1]) else { return false }
            return Window.same(Date(timeIntervalSince1970: epoch), resets)
        }
        guard !sent, !pending.contains(key) else { return }
        pending.insert(key)
        deliver(title: title, body: body) { [weak self] ok in
            guard let self else { return }
            self.pending.remove(key)
            guard ok else { return }
            self.store.state.notified.append(key)
            self.store.save()
        }
    }

    /// Posts a sample alert, asking for permission first if it was never asked, and reports
    /// whether the system lets this app notify.
    func test(_ done: @escaping @MainActor (Bool) -> Void) {
        guard let center else { return done(false) }
        center.getNotificationSettings { settings in
            let status = settings.authorizationStatus
            Task { @MainActor in
                if status == .notDetermined {
                    center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                        Task { @MainActor in self.finishTest(granted, done) }
                    }
                } else {
                    self.finishTest(Self.allows(status), done)
                }
            }
        }
    }

    private func finishTest(_ allowed: Bool, _ done: @MainActor (Bool) -> Void) {
        authorized = allowed
        authorizationCheckedAt = Date()
        if allowed { deliver(title: "Claude Meter", body: "Notifications are working. You'll hear from it at 80% and 95%.") }
        done(allowed)
    }

    private func deliver(title: String, body: String, done: (@MainActor (Bool) -> Void)? = nil) {
        guard let center else { done?(false); return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)) { error in
            Task { @MainActor in done?(error == nil) }
        }
    }
}
