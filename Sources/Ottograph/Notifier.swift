import Foundation
import UserNotifications

/// Thin wrapper over UNUserNotificationCenter with repeat suppression, so a
/// failure that recurs on every From change doesn't stack up banners.
///
/// Notifications need a bundle identifier, so bare `swift run` builds post
/// nothing rather than crashing.
@MainActor
enum Notifier {
    private static var lastPosted: [String: Date] = [:]
    private static let repeatWindow: TimeInterval = 60

    static var isAvailable: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundlePath.hasSuffix(".app")
    }

    static func requestAuthorization() {
        guard isAvailable else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
    }

    /// Posts a banner. Identical messages within a minute are dropped.
    static func post(title: String, body: String) {
        guard isAvailable else { return }
        let key = title + "\u{1}" + body
        let now = Date()
        if let last = lastPosted[key], now.timeIntervalSince(last) < repeatWindow { return }
        lastPosted[key] = now

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        )
    }
}
