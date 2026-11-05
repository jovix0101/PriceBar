import SwiftUI
import PriceBarCore

/// The colors a movement is drawn in.
///
/// Kept out of `Store`, which knows nothing of SwiftUI: the store holds the
/// choice, and the views turn it into a color. The line and the percentage
/// both ask here, so that the two never disagree.
extension ChangeColors {
    /// The pair the panel and the settings page use: deep enough to read on a
    /// white card. These are the product page's own text colours.
    static let upColour = NSColor(srgbRed: 0x1F / 255, green: 0x9D / 255, blue: 0x4D / 255, alpha: 1)
    static let downColour = NSColor(srgbRed: 0xD3 / 255, green: 0x3A / 255, blue: 0x2C / 255, alpha: 1)

    /// The pair the menu bar uses. A menu bar sits on a dark translucent bar
    /// where the panel's deep green turns to mud and its red to brick, so the
    /// bright set takes over: the same two hues the product page draws its
    /// example menu bar in.
    ///
    /// Fixed sRGB rather than `NSColor.systemGreen` / `.systemRed`: those are
    /// dynamic, and the button's effective appearance is the vibrant light one
    /// even on a dark bar, so the system pair comes out brighter and more
    /// fluorescent there than anything on the page.
    static let upOnBarColour = NSColor(srgbRed: 0x34 / 255, green: 0xC7 / 255, blue: 0x59 / 255, alpha: 1)
    static let downOnBarColour = NSColor(srgbRed: 0xFF / 255, green: 0x69 / 255, blue: 0x61 / 255, alpha: 1)

    /// The colour a movement is drawn in on a light background, or nil when it
    /// has no side of its own and there is nothing to colour.
    func nsColour(for change: Double) -> NSColor? {
        guard let green = isGreen(change) else { return nil }
        return green ? Self.upColour : Self.downColour
    }

    /// The same, for the menu bar.
    func barColour(for change: Double) -> NSColor? {
        guard let green = isGreen(change) else { return nil }
        return green ? Self.upOnBarColour : Self.downOnBarColour
    }

    /// SwiftUI's share of the above, for the panel and the settings page.
    func color(for change: Double) -> Color {
        guard let colour = nsColour(for: change) else { return .secondary }
        return Color(nsColor: colour)
    }
}
