import AppKit

/// The price as the menu bar item draws it.
///
/// The menu bar sets its label in one font at one size and ignores a font
/// asked for in the label itself, so a "$" comes out the size of the digits
/// and reads as one more digit: "$77601" can be taken for "877601" at a
/// glance. Drawing the text into an image is the way out — the coin and the
/// symbol are set a size down and sit on the digits' baseline, as they do in
/// a printed price list — and a template image takes the menu bar's own tint,
/// so it looks native in light and dark alike.
///
/// Every image is drawn on the same width, the widest of the coins taking
/// turns: a label that grows and shrinks moves everything beside it in the
/// menu bar, which is worse to look at than a few points of slack.
enum MenuBarPrice {
    /// The coin on the left, the currency a size down, then the price.
    static func attributed(coin: String, symbol: String, amount: String) -> NSAttributedString {
        let smallFont = NSFont.systemFont(ofSize: 10, weight: .medium)
        let digitsFont = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        let colour = NSColor.black

        let text = NSMutableAttributedString(
            string: coin + " ",
            attributes: [.font: smallFont, .foregroundColor: colour]
        )
        text.append(NSAttributedString(
            string: symbol,
            attributes: [.font: smallFont, .foregroundColor: colour]
        ))
        text.append(NSAttributedString(
            string: " " + amount,
            attributes: [.font: digitsFont, .foregroundColor: colour]
        ))
        return text
    }

    /// How wide this coin's label would be, drawn on its own.
    static func width(coin: String, symbol: String, amount: String) -> CGFloat {
        ceil(attributed(coin: coin, symbol: symbol, amount: amount).size().width)
    }

    /// `width` is the room the label has: the widest label of the coins the
    /// menu bar shows, so that the item never changes size between them.
    static func image(coin: String, symbol: String, amount: String, width: CGFloat) -> NSImage {
        let text = attributed(coin: coin, symbol: symbol, amount: amount)
        let size = text.size()

        // Half a point of headroom on the left: the glyphs of a font's
        // bounding box can be a hair wider than the box it reports, and a
        // clipped edge is visible at this size.
        let canvas = NSSize(width: max(width, ceil(size.width)) + 1, height: ceil(size.height))
        let image = NSImage(size: canvas, flipped: false) { _ in
            text.draw(at: NSPoint(x: 0.5, y: 0))
            return true
        }
        image.isTemplate = true
        return image
    }

    @MainActor static func image(for store: Store) -> NSImage? {
        guard let quote = store.menuBarQuote else { return nil }
        return image(
            coin: quote.coin,
            symbol: store.currency.symbol,
            amount: store.amount(quote.price),
            width: store.menuBarWidth
        )
    }
}
