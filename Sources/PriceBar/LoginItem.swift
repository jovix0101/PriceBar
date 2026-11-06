import Foundation
import PriceBarCore
import ServiceManagement

/// Whether the app starts when the user logs in.
///
/// The app has to be a signed bundle for the system to accept it as a login
/// item, so an app run straight from Xcode, or `swift build`, cannot be one:
/// the toggle reports that instead of failing silently.
enum LoginItem {
    /// False when the bundle cannot be a login item at all.
    static var supported: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundlePath.hasSuffix(".app")
    }

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Turns the login item on or off, and returns an error message when the
    /// system refuses.
    @discardableResult
    static func setEnabled(_ enabled: Bool, _ strings: Strings = Strings()) -> String? {
        guard supported else { return strings.loginNeedsApp }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
