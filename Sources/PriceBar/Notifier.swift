import AppKit
import Foundation
import UserNotifications

/// Shows the system's notifications.
///
/// Notifications need an app bundle: macOS files them under the bundle
/// identifier, and `UNUserNotificationCenter.current()` throws without one.
/// Running the executable straight from Xcode or `swift run` has no bundle,
/// so the app keeps quiet there rather than crashing; the alerts still arm
/// and fire, they just show nothing.
enum Notifier {
    static var available: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    /// Whether the app may show notifications, as the system sees it now.
    /// The user can change it while the app runs, so this asks each time
    /// rather than remembering an answer.
    static func authorization() async -> UNAuthorizationStatus {
        guard available else { return .denied }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus
    }

    /// Asks for permission once, at launch, so that the first alert does not
    /// wait for an answer nobody is looking at.
    static func requestAuthorization() {
        guard available else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func send(title: String, body: String) {
        guard available else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    /// Opens the pane of System Settings where the user allows or blocks the
    /// app's notifications.
    static func openSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!
        NSWorkspace.shared.open(url)
    }
}
