import AppKit
import PriceBarCore

/// The app: an item in the menu bar, showing a price, and a panel of prices
/// below it.
///
/// Started from `main.swift` rather than a SwiftUI `App`: a SwiftUI app needs
/// a scene, and every scene of a menu bar app that has no window is a window
/// it does not want — `Settings { EmptyView() }` opens one anyway, empty and
/// titled, the moment the app launches. The only scene worth having here is
/// the settings window, and that is a window this app makes itself.
///
/// The menus say their commands in the language the settings ask for, so
/// they are built again whenever that changes: they are AppKit's, and a
/// title is a string written once, not a view that redraws.
final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor let store = Store()
    @MainActor private var statusItem: StatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The delegate calls this on the main thread, but the protocol says
        // nothing about actors: say so, rather than hopping through a task and
        // drawing the item a turn later than the menu bar is ready for.
        MainActor.assumeIsolated {
            // The app's own menu bar is AppKit's: it is built again in the
            // new language rather than redrawn.
            store.languageDidChange = { [weak self] in self?.installMenuBar() }
            installMenuBar()
            Notifier.requestAuthorization()
            statusItem = StatusItem(store: store)
            store.start()
        }
    }

    /// A menu bar app keeps the commands a Mac app is expected to have —
    /// Settings on ⌘, and Quit on ⌘Q — in a menu bar of its own, which shows
    /// while one of its windows has the keyboard.
    @MainActor private func installMenuBar() {
        let strings = store.strings
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        let settings = appMenu.addItem(
            withTitle: strings.settingsItem,
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settings.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: strings.hideApp,
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        appMenu.addItem(
            withTitle: strings.quitItem,
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        // ⌘A, ⌘C, ⌘V and the rest are not built into a text field: they are
        // menu items the field answers to. Without an Edit menu the proxy
        // address could be typed but not pasted. Nobody sees this menu — the
        // app has no menu bar on screen — but its shortcuts work.
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: strings.editMenu)
        editMenu.addItem(withTitle: strings.undoItem, action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: strings.redoItem, action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: strings.cutItem, action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: strings.copyItem, action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: strings.pasteItem, action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: strings.selectAllItem, action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

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
