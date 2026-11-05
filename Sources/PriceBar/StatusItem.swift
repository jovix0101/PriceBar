import AppKit
import SwiftUI
import PriceBarCore

/// The app's item in the menu bar, and the panel that opens under it.
///
/// An `NSStatusItem` of the app's own rather than SwiftUI's `MenuBarExtra`.
/// `MenuBarExtra` keeps the panel's view alive after it closes, so the view
/// cannot tell it has been closed — the lines were read once and never again.
/// It also refuses a right click and gives no way to reach the item's button.
/// Owning the item answers all three: the popover says when it opens and
/// closes, the button answers both clicks, and the label is set on the button
/// whenever the store changes.
@MainActor
final class StatusItem: NSObject, NSPopoverDelegate {
    private let store: Store
    private let item: NSStatusItem
    private let popover = NSPopover()

    init(store: Store) {
        self.store = store
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        let button = item.button
        button?.target = self
        button?.action = #selector(clicked)
        button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button?.alignment = .left

        let hosting = NSHostingController(rootView: PanelView(store: store))
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
        popover.behavior = .transient
        popover.delegate = self

        draw()
        follow()
    }

    // MARK: - The label

    /// Draws what the store says. Called once at start and again whenever the
    /// store changes.
    private func draw() {
        let labels = MenuBarPrice.labels(for: store)
        guard let button = item.button else { return }

        guard !labels.isEmpty else {
            button.attributedTitle = NSAttributedString(string: "—")
            button.setAccessibilityLabel("价格")
            return
        }

        button.attributedTitle = MenuBarPrice.title(
            labels,
            choice: store.menuBarTint,
            colors: store.changeColors
        )
        button.setAccessibilityLabel(store.menuBarReading)
    }

    /// Redraws whenever anything the label is made of changes. The store is
    /// observable from outside SwiftUI too; each change re-arms the watch,
    /// because a watch fires once.
    private func follow() {
        withObservationTracking {
            _ = store.menuBarQuotes
            _ = store.currency
            _ = store.rate
            _ = store.menuBarTint
            _ = store.changeColors
        } onChange: { [weak self] in
            // The change is still being written when this is called, so the
            // redraw waits for the next turn of the run loop.
            Task { @MainActor in
                guard let self else { return }
                self.draw()
                self.follow()
            }
        }
    }

    // MARK: - The panel

    @objc private func clicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            togglePanel()
        }
    }

    private func togglePanel() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        guard let button = item.button else { return }
        // A popover takes the keyboard only in the active app, and the panel
        // has text fields: the coin to add, the price to watch.
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func popoverDidShow(_ notification: Notification) {
        store.panelOpened()
    }

    func popoverDidClose(_ notification: Notification) {
        store.panelClosed()
    }

    /// The two commands a menu bar app cannot be left without, since it has
    /// no menu bar of its own to put them in while another app is in front.
    private func showMenu() {
        let menu = NSMenu()
        let settings = menu.addItem(
            withTitle: "设置…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settings.target = self
        menu.addItem(.separator())
        let quit = menu.addItem(
            withTitle: "退出 PriceBar",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quit.target = NSApp

        guard let button = item.button else { return }
        if popover.isShown { popover.performClose(nil) }

        // Nothing is drawn behind the item while its menu is up — the menu
        // bar is transparent, and a status item's own button is not filled in
        // — so a label in a colour of its own can stay as it is. Inverting it
        // here made black text white over the wallpaper, which read worse.
        // Popped up at the item's bottom edge, which is where the system's
        // own menu bar items put theirs. The app is brought forward first:
        // a menu is drawn only for the active app, and the item can be
        // clicked while another one is in front. The button is flipped, so
        // its bottom edge is `maxY`.
        NSApp.activate(ignoringOtherApps: true)
        menu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: button.bounds.maxY + 9),
            in: button
        )
    }

    @objc private func openSettings() {
        SettingsWindow.shared.show(store: store)
    }
}
