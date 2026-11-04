import AppKit
import SwiftUI
import PriceBarCore

/// The app's item in the menu bar, and the panel that opens under it.
///
/// An `NSStatusItem` of the app's own rather than SwiftUI's `MenuBarExtra`.
/// `MenuBarExtra` keeps the panel's view alive after it closes, so the view
/// cannot tell it has been closed — the lines were read once and never again,
/// and the menu bar stopped taking turns. It also refuses a right click and
/// gives no way to animate the label. Owning the item answers all three: the
/// popover says when it opens and closes, the button answers both clicks, and
/// the label is an image this file draws, one frame at a time.
@MainActor
final class StatusItem: NSObject, NSPopoverDelegate {
    private let store: Store
    private let item: NSStatusItem
    private let popover = NSPopover()

    /// The frame-by-frame scroll, while one is running.
    private var scroll: Timer?
    /// What the item is showing now, so that a change of coin can be told
    /// from a change of price.
    private var showing: MenuBarPrice.Label?

    /// The colour the label is drawn in, or nil to keep it a template image
    /// and let the menu bar tint it.
    private var tint: NSColor? { MenuBarPrice.tint(for: store) }

    init(store: Store) {
        self.store = store
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        let button = item.button
        button?.target = self
        button?.action = #selector(clicked)
        button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button?.imagePosition = .imageOnly
        button?.imageScaling = .scaleNone

        let hosting = NSHostingController(rootView: PanelView(store: store))
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
        popover.behavior = .transient
        popover.delegate = self

        draw()
        follow()
    }

    // MARK: - The label

    /// Draws what the store says, animating if the coin is not the one on
    /// screen. Called once at start and again whenever the store changes.
    private func draw() {
        guard let label = MenuBarPrice.label(for: store) else {
            scroll?.invalidate()
            scroll = nil
            showing = nil
            item.button?.image = nil
            item.button?.title = "—"
            item.button?.setAccessibilityLabel("价格")
            return
        }

        item.button?.title = ""
        item.button?.setAccessibilityLabel("\(label.coin) \(label.symbol)\(label.amount)")

        let width = store.menuBarWidth
        let previous = showing
        showing = label

        // A price that ticked up is not worth a scroll: only a new coin is.
        // The first label has nothing to scroll from, and Reduce Motion asks
        // for no motion at all.
        guard let previous, previous.coin != label.coin,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        else {
            scroll?.invalidate()
            scroll = nil
            item.button?.image = MenuBarPrice.image(label, width: width, tint: tint)
            return
        }
        roll(from: previous, to: label, width: width)
    }

    /// Slides `to` up from below while `from` leaves through the top, both
    /// cut off by the item's height. 200 ms with an ease-out tail: fast
    /// enough to read as a turn, slow enough to follow which coin is which.
    private func roll(from: MenuBarPrice.Label, to: MenuBarPrice.Label, width: CGFloat) {
        scroll?.invalidate()

        let started = Date()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.step(from: `from`, to: to, width: width, started: started)
            }
        }
        // The common modes, so that the scroll keeps its frames while a menu
        // is tracking or a window is being dragged.
        RunLoop.main.add(timer, forMode: .common)
        scroll = timer
    }

    /// One frame of the scroll. The last one puts the new label down on its
    /// own, so that the item ends on a sharp image rather than a frame of
    /// something in transit.
    private func step(
        from old: MenuBarPrice.Label,
        to new: MenuBarPrice.Label,
        width: CGFloat,
        started: Date
    ) {
        let elapsed = Date().timeIntervalSince(started) / 0.2
        guard elapsed < 1 else {
            scroll?.invalidate()
            scroll = nil
            item.button?.image = MenuBarPrice.image(new, width: width, tint: tint)
            return
        }
        let eased = 1 - pow(1 - elapsed, 3)
        item.button?.image = MenuBarPrice.scrolling(
            from: old,
            to: new,
            width: width,
            progress: CGFloat(eased),
            tint: tint
        )
    }

    /// Redraws whenever anything the label is made of changes. The store is
    /// observable from outside SwiftUI too; each change re-arms the watch,
    /// because a watch fires once.
    private func follow() {
        withObservationTracking {
            _ = store.menuBarQuote
            _ = store.menuBarWidth
            _ = store.currency
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
