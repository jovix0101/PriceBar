import AppKit
import SwiftUI
import PriceBarCore

/// The settings window.
///
/// A window of the app's own rather than SwiftUI's `Settings` scene: a menu
/// bar app is not the active app when its panel opens, and the scene only
/// answers once it is. This one opens whenever it is asked to, and brings the
/// app forward with it.
@MainActor
final class SettingsWindow {
    static let shared = SettingsWindow()

    private var window: NSWindow?

    func show(store: Store) {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(store: store))
            let window = NSWindow(contentViewController: hosting)
            window.title = "PriceBar 设置"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
