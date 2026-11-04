import SwiftUI
import PriceBarCore

/// The app: an item in the menu bar, showing a price, and a panel of prices
/// below it.
@main
struct PriceBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            PanelView(store: delegate.store)
        } label: {
            MenuBarLabel(store: delegate.store)
        }
        // A window, not a menu: the panel holds controls of its own.
        .menuBarExtraStyle(.window)
    }
}

/// Owns the store, so that the app starts reading prices as it launches,
/// before the user opens the panel.
final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor let store = Store()

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenuBar()
        Notifier.requestAuthorization()
        Task { @MainActor in store.start() }
    }

    /// A menu bar app keeps the commands a Mac app is expected to have —
    /// Settings on ⌘, and Quit on ⌘Q — in a menu bar of its own, which shows
    /// while one of its windows has the keyboard.
    private func installMenuBar() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏 PriceBar", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "退出 PriceBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        for item in appMenu.items where item.action != nil {
            item.target = item.action == #selector(openSettings) ? self : nil
        }
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        NSApplication.shared.mainMenu = mainMenu
    }

    @objc @MainActor private func openSettings() {
        SettingsWindow.shared.show(store: store)
    }

    /// A menu bar app stays running when its panel closes: nothing to do.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

/// The menu bar item: the price of the coin the user chose, or a dash until
/// the first one arrives.
private struct MenuBarLabel: View {
    let store: Store

    var body: some View {
        if let image = MenuBarPrice.image(for: store) {
            Image(nsImage: image)
                .accessibilityLabel(accessibilityText)
        } else {
            Text("—")
        }
    }

    private var accessibilityText: String {
        guard let quote = store.menuBarQuote else { return "价格" }
        return "\(quote.coin) \(store.money(quote.price))"
    }
}
