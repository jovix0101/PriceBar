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
final class SettingsWindow: NSObject, NSWindowDelegate {
    static let shared = SettingsWindow()

    private var window: NSWindow?
    private var tabs: SettingsTabs?

    /// Opens the window, on the page asked for or on the one it was left at.
    func show(store: Store, page: SettingsPage? = nil) {
        if window == nil {
            let tabs = SettingsTabs(store: store)
            let window = NSWindow(contentViewController: tabs)
            window.styleMask = [.titled, .closable]
            window.toolbarStyle = .preference
            window.isReleasedWhenClosed = false
            window.delegate = self
            self.tabs = tabs
            self.window = window
            tabs.fitWindow(animate: false)
            window.center()
        }
        if let page {
            tabs?.selectedTabViewItemIndex = page.rawValue
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// A closed window keeps its field focused, and the app hands that field
    /// the keyboard the next time it is brought forward: what was typed into
    /// the panel went to the proxy address of a window no longer on screen.
    /// The field lets go as the window closes.
    func windowWillClose(_ notification: Notification) {
        window?.makeFirstResponder(nil)
    }
}

/// The pages, as toolbar buttons along the top the way the system's own
/// settings windows have them. The window takes the height of the page it
/// shows, top edge held still, so a short page is not left standing in a
/// tall window.
private final class SettingsTabs: NSTabViewController {
    private let store: Store

    init(store: Store) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
        tabStyle = .toolbar
        // The window's title names the page it shows.
        canPropagateSelectedChildViewControllerTitle = true
        for page in SettingsPage.allCases {
            let hosting = NSHostingController(rootView: SettingsView(store: store, page: page))
            // A page grows and shrinks as it is used — the proxy address
            // appears, a note gets a second line — and the window follows.
            hosting.sizingOptions = [.preferredContentSize]
            hosting.title = page.title(store.strings)
            let item = NSTabViewItem(viewController: hosting)
            item.label = page.title(store.strings)
            item.image = NSImage(
                systemSymbolName: page.symbol,
                accessibilityDescription: page.title(store.strings)
            )
            addTabViewItem(item)
        }
        watchLanguage()
    }

    /// The pages read the language themselves, but the toolbar buttons are
    /// AppKit's and only say what they were last told: they are told again
    /// whenever the language changes.
    private func watchLanguage() {
        withObservationTracking {
            _ = store.language
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.retitle()
                self?.watchLanguage()
            }
        }
    }

    private func retitle() {
        for (index, page) in SettingsPage.allCases.enumerated() {
            let title = page.title(store.strings)
            tabViewItems[index].label = title
            tabViewItems[index].viewController?.title = title
        }
        // The window's own title is copied from the page when a tab is
        // picked, so it is said again here rather than waiting for that.
        view.window?.title = tabViewItems[selectedTabViewItemIndex].label
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        fitWindow(animate: true)
    }

    override func preferredContentSizeDidChange(for viewController: NSViewController) {
        super.preferredContentSizeDidChange(for: viewController)
        guard viewController == tabViewItems[selectedTabViewItemIndex].viewController else { return }
        fitWindow(animate: true)
    }

    /// Sizes the window to the page on show, keeping its top edge where it is.
    func fitWindow(animate: Bool) {
        guard let window = view.window,
              let page = tabViewItems[selectedTabViewItemIndex].viewController
        else { return }
        let size = page.view.fittingSize
        let content = window.contentRect(forFrameRect: window.frame)
        guard content.size != size else { return }
        let target = NSRect(
            x: content.minX, y: content.maxY - size.height,
            width: size.width, height: size.height
        )
        window.setFrame(window.frameRect(forContentRect: target), display: true,
                        animate: animate && window.isVisible)
    }
}
