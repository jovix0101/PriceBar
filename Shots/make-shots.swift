import AppKit
import SwiftUI
import PriceBarCore

/// Draws the four settings pages into docs/ as 2× PNGs, for the product page:
/// once in each language, since the page has one of each and shows the app as
/// that reader would see it.
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
    let quotes = [
        Quote(coin: "BTC", price: 80_575, change: 2.89),
        Quote(coin: "ETH", price: 2_424, change: 5.20),
        Quote(coin: "SOL", price: 132.44, change: 1.20),
        Quote(coin: "XAU.P", price: 4_092, change: 0.95),
        Quote(coin: "AAPL.P", price: 353.16, change: -1.20),
    ]

    // A day for each line: the same shape every run, since a picture that
    // changes when nothing did is one more thing to look at in a diff.
    func line(from start: Double, drift: Double, wobble: Double) -> [Double] {
        var value = start
        return (0..<24).map { hour in
            value *= 1 + drift + wobble * sin(Double(hour) * 1.1)
            return value
        }
    }
    let lines = [
        "BTC": line(from: 76_000, drift: 0.0024, wobble: 0.004),
        "ETH": line(from: 2_260, drift: 0.0040, wobble: 0.006),
        "SOL": line(from: 128, drift: 0.0020, wobble: 0.007),
        "XAU.P": line(from: 4_050, drift: 0.0008, wobble: 0.002),
        "AAPL.P": line(from: 360, drift: -0.0018, wobble: 0.003),
    ]

    // English keeps the plain names, since the English page is the one at /.
    let names: [SettingsPage: String] = [
        .general: "general",
        .menuBar: "menubar",
        .panel: "panel",
        .source: "source",
    ]

    let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "docs"

    for language in Language.allCases {
        var drawn = settings
        drawn.language = language
        let store = Store(settings: drawn, quotes: quotes, lines: lines)
        let suffix = language == .english ? "" : "-zh"

        for page in SettingsPage.allCases {
            let name = "settings-\(names[page] ?? String(page.rawValue))\(suffix).png"
            snapshot(
                SettingsView(store: store, page: page),
                width: 380,
                label: page.title(Strings(language)),
                to: out, name: name
            )
        }

        // The panel itself: what the menu bar item opens.
        snapshot(
            PanelView(store: store),
            width: nil,
            label: "panel",
            to: out, name: "panel\(suffix).png"
        )
    }
}

/// Draws one view into `out/name.png`, twice the size of the view on screen.
///
/// Through `NSHostingView` rather than `ImageRenderer`: the segmented pickers
/// and the switch are AppKit controls, and `ImageRenderer` draws them as
/// yellow "unsupported" blocks. The view goes into a real window, so the
/// controls have a window to draw their background against.
@MainActor
func snapshot(
    _ view: some View,
    width: CGFloat?,
    label: String,
    to out: String,
    name: String
) {
    let root = view
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.colorScheme, .light)
    let hosting = NSHostingView(rootView: root)
    hosting.frame = NSRect(x: 0, y: 0, width: width ?? 200, height: 10)

    // Light appearance, whatever mode this Mac is in: the page is white.
    let window = NSWindow(
        contentRect: hosting.frame,
        styleMask: [.titled], backing: .buffered, defer: false
    )
    window.appearance = NSAppearance(named: .aqua)
    window.contentView = hosting
    window.setIsVisible(true)
    hosting.layoutSubtreeIfNeeded()

    let fitting = hosting.fittingSize
    let size = CGSize(width: width ?? ceil(fitting.width), height: ceil(fitting.height))
    hosting.frame = NSRect(origin: .zero, size: size)
    window.setContentSize(size)
    hosting.layoutSubtreeIfNeeded()
    hosting.displayIfNeeded()

    let scale: CGFloat = 2
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else {
        print("no bitmap for \(label)")
        return
    }
    rep.size = size
    hosting.cacheDisplay(in: hosting.bounds, to: rep)
    window.setIsVisible(false)

    guard let data = rep.representation(using: .png, properties: [:]) else {
        print("no PNG for \(label)")
        return
    }
    let url = URL(fileURLWithPath: out).appendingPathComponent(name)
    try? data.write(to: url)
    print("\(label) -> \(url.lastPathComponent) \(rep.pixelsWide)×\(rep.pixelsHigh)")
}

MainActor.assumeIsolated { main() }
