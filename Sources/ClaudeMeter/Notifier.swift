import Foundation
import UserNotifications

/// Posts once per window per threshold, and once when a hot 5-hour window resets.
@MainActor
final class Notifier {
    private let store: StateStore
    private let center: UNUserNotificationCenter?
    private let thresholds: [Double] = [80, 95]
    private var currentReset: Date?
    private var peak = 0.0

    init(store: StateStore) {
        self.store = store
        // UNUserNotificationCenter traps outside an app bundle (e.g. `swift run`).
        center = Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
        center?.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func check(_ s: Snapshot, now: Date) {
        guard center != nil, s.loaded else { return }

        for w in [s.fiveHour, s.weekly].compactMap({ $0 }) where !w.idle {
            guard let resets = w.resetsAt else { continue }
            for t in thresholds where w.pct >= t {
                let key = "\(w.title)|\(Int(resets.timeIntervalSince1970))|\(Int(t))"
                guard !store.state.notified.contains(key) else { continue }
                store.state.notified.append(key)
                store.save()
                post("Claude \(w.title.lowercased()) at \(Fmt.pct(w.pct))",
                     "Resets \(Fmt.when(resets)), in \(Fmt.duration(resets.timeIntervalSince(now))).")
            }
        }

        guard let f = s.fiveHour else { return }
        if f.resetsAt != currentReset {
            if let previous = currentReset, now >= previous, peak >= thresholds[0] {
                post("Claude 5-hour window reset", "You're back to a full window.")
            }
            currentReset = f.resetsAt
            peak = f.pct
        } else {
            peak = max(peak, f.pct)
        }
    }

    private func post(_ title: String, _ body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        center?.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
