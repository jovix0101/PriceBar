import AppKit
import SwiftUI
import PriceBarCore

/// Draws the four settings pages into docs/ as 2× PNGs, for the product page.
///
/// Through `NSHostingView` rather than `ImageRenderer`: the segmented pickers
/// and the switch are AppKit controls, and `ImageRenderer` draws them as
/// yellow "unsupported" blocks. The view goes into a real window, so the
/// controls have a window to draw their background against, and the bitmap
/// is half again as wide as the view so that Retina screens get a sharp page.
@MainActor
func main() {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)

    // The pages the product page shows, with a store that looks like an app
    // someone has been using for a while.
    var settings = AppSettings()
    settings.coins = ["BTC", "ETH", "SOL", "XAU.P", "AAPL.P"]
    settings.menuBarCoins = ["BTC", "ETH", "XAU.P"]
    settings.currency = .usd
    settings.interval = 10
    settings.panelRows = 8
    settings.menuBarTint = .automatic
    settings.source = .binance
    settings.proxyMode = .direct
    let store = Store(settings: settings, quotes: [
        Quote(coin: "BTC", price: 80_575, change: 2.89),
        Quote(coin: "ETH", price: 2_424, change: 5.20),
        Quote(coin: "SOL", price: 132.44, change: 1.20),
        Quote(coin: "XAU.P", price: 4_092, change: 0.95),
        Quote(coin: "AAPL.P", price: 353.16, change: -1.20),
    ])

    let pageNames: [SettingsPage: String] = [
        .general: "settings-general.png",
        .menuBar: "settings-menubar.png",
        .panel: "settings-panel.png",
        .source: "settings-source.png",
    ]

    let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "docs"
    let width: CGFloat = 380
    let scale: CGFloat = 2

    for page in SettingsPage.allCases {
        let root = SettingsView(store: store, page: page)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, .light)
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: 10)

        // Light appearance, whatever mode this Mac is in: the page is white.
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = hosting
        window.setIsVisible(true)
        hosting.layoutSubtreeIfNeeded()

        let height = ceil(hosting.fittingSize.height)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
        window.setContentSize(NSSize(width: width, height: height))
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()

        // A rep twice the size of the view, drawn as if it were the view's own
        // size: that is what makes the PNG 2×.
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else {
            print("no bitmap for \(page.title)")
            continue
        }
        rep.size = NSSize(width: width, height: height)
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        window.setIsVisible(false)

        guard let data = rep.representation(using: .png, properties: [:]) else {
            print("no PNG for \(page.title)")
            continue
        }
        let url = URL(fileURLWithPath: out).appendingPathComponent(pageNames[page] ?? "settings-\(page.rawValue).png")
        try? data.write(to: url)
        print("\(page.title) -> \(url.path) \(rep.pixelsWide)×\(rep.pixelsHigh)")
    }
}

MainActor.assumeIsolated { main() }
