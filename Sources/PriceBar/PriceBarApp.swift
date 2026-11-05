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
final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor let store = Store()
    @MainActor private var statusItem: StatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The delegate calls this on the main thread, but the protocol says
        // nothing about actors: say so, rather than hopping through a task and
        // drawing the item a turn later than the menu bar is ready for.
        MainActor.assumeIsolated {
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
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        let settings = appMenu.addItem(
            withTitle: "设置…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settings.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "隐藏 PriceBar",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        appMenu.addItem(
            withTitle: "退出 PriceBar",
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
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
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
