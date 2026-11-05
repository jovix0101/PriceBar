import SwiftUI
import PriceBarCore

/// The colors a movement is drawn in.
///
/// Kept out of `Store`, which knows nothing of SwiftUI: the store holds the
/// choice, and the views turn it into a color. The line, the percentage and
/// the menu bar all ask here, so that the three can never disagree.
extension ChangeColors {
    /// Green up, red down, in the two colours Binance's own market page uses.
    ///
    /// Fixed sRGB rather than `NSColor.systemGreen` / `.systemRed`: those are
    /// dynamic, and the status button's effective appearance is the vibrant
    /// light one even on a dark bar, so the system pair comes out brighter and
    /// more fluorescent than the numbers in a browser tab next to it.
    static let upColour = NSColor(srgbRed: 0x2E / 255, green: 0xBD / 255, blue: 0x85 / 255, alpha: 1)
    static let downColour = NSColor(srgbRed: 0xF6 / 255, green: 0x46 / 255, blue: 0x5D / 255, alpha: 1)

    /// The colour a movement is drawn in, or nil when it has no side of its
    /// own — one that prints as "0%" — and there is nothing to colour.
    func nsColour(for change: Double) -> NSColor? {
        guard let green = isGreen(change) else { return nil }
        return green ? Self.upColour : Self.downColour
    }

    /// SwiftUI's share of the above, for the panel and the settings page.
    func color(for change: Double) -> Color {
        guard let colour = nsColour(for: change) else { return .secondary }
        return Color(nsColor: colour)
    }
}
