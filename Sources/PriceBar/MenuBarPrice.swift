import AppKit
import PriceBarCore

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
    /// One coin's label: the coin on the left, the currency a size down, then
    /// the price. Compared to tell a new coin from a new price for the same
    /// one.
    struct Label: Equatable {
        let coin: String
        let symbol: String
        let amount: String
        /// The 24h change after the price, arrow and all: "▲2.02%". Empty when
        /// there is none to show.
        let change: String
    }

    static func attributed(_ label: Label) -> NSAttributedString {
        let smallFont = NSFont.systemFont(ofSize: 10, weight: .medium)
        let digitsFont = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        let colour = NSColor.black

        let text = NSMutableAttributedString(
            string: label.coin + " ",
            attributes: [.font: smallFont, .foregroundColor: colour]
        )
        text.append(NSAttributedString(
            string: label.symbol,
            attributes: [.font: smallFont, .foregroundColor: colour]
        ))
        text.append(NSAttributedString(
            string: " " + label.amount,
            attributes: [.font: digitsFont, .foregroundColor: colour]
        ))
        if !label.change.isEmpty {
            // A step lighter: the price is what the item is for, the change is
            // a note on it. Template images keep the alpha they were drawn
            // with, so this dims against the menu bar's own tint.
            text.append(NSAttributedString(
                string: " " + label.change,
                attributes: [
                    .font: smallFont,
                    .foregroundColor: colour.withAlphaComponent(0.75),
                ]
            ))
        }
        return text
    }

    /// How wide this coin's label would be, drawn on its own.
    static func width(of label: Label) -> CGFloat {
        ceil(attributed(label).size().width)
    }

    /// The change text to measure the item's width against.
    ///
    /// A change that rounds to nothing prints as nothing, and a label that
    /// loses forty points the moment a coin crosses flat would shift every
    /// icon beside it. So an empty change is measured as if it were there.
    static func widthReserve(_ change: Double) -> String {
        let text = formatArrowed(change)
        return text.isEmpty ? "▲00.00%" : text
    }

    /// `width` is the room the label has: the widest label of the coins the
    /// menu bar shows, so that the item never changes size between them.
    static func image(_ label: Label, width: CGFloat) -> NSImage {
        let text = attributed(label)
        let size = text.size()
        let canvas = NSSize(width: contentWidth(text, width), height: ceil(size.height))
        let image = NSImage(size: canvas, flipped: false) { _ in
            text.draw(at: NSPoint(x: 0.5, y: 0))
            return true
        }
        image.isTemplate = true
        return image
    }

    /// A frame of the scroll: `progress` runs 0 to 1, moving the old label up
    /// and out while the new one comes up from below it. Both are cut off at
    /// the item's edges, which is what makes it read as one label turning
    /// rather than two sliding past each other.
    static func scrolling(
        from old: Label,
        to new: Label,
        width: CGFloat,
        progress: CGFloat
    ) -> NSImage {
        let out = attributed(old)
        let into = attributed(new)
        let lift = ceil(max(out.size().height, into.size().height))
        let canvas = NSSize(
            width: contentWidth(out.size().width > into.size().width ? out : into, width),
            height: lift
        )

        let image = NSImage(size: canvas, flipped: false) { _ in
            let travel = progress * lift
            // The old label leaves upward, the new one follows it into the
            // space it is leaving, so the two are always exactly one apart.
            out.draw(at: NSPoint(x: 0.5, y: travel))
            into.draw(at: NSPoint(x: 0.5, y: travel - lift))
            return true
        }
        image.isTemplate = true
        return image
    }

    /// The label the menu bar is showing now, or nil before the first price.
    @MainActor static func label(for store: Store) -> Label? {
        guard let quote = store.menuBarQuote else { return nil }
        return Label(
            coin: quote.coin,
            symbol: store.currency.symbol,
            amount: store.amount(quote.price),
            change: formatArrowed(quote.change)
        )
    }

    @MainActor static func image(for store: Store) -> NSImage? {
        guard let label = label(for: store) else { return nil }
        return image(label, width: store.menuBarWidth)
    }

    /// Half a point of headroom on the left: the glyphs of a font's bounding
    /// box can be a hair wider than the box it reports, and a clipped edge is
    /// visible at this size.
    private static func contentWidth(_ text: NSAttributedString, _ width: CGFloat) -> CGFloat {
        max(width, ceil(text.size().width)) + 1
    }
}
