import AppKit

/// A menu bar app with no window to open at launch, so no scene to show:
/// the item is put in the menu bar by the delegate, and the panel and the
/// settings window are windows the app makes for itself.
///
/// `NSApplicationMain` would read `Info.plist` and start an app of its own,
/// which a Swift package's executable cannot rely on; setting the delegate up
/// by hand is the same few lines and says what happens. The work is handed to
/// the main actor from here, because top-level code is not on it.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
