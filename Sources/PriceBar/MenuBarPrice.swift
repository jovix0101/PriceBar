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
/// Every image is drawn on one width, the widest of the coins taking turns,
/// and the price is drawn against the right edge of it. The room a narrower
/// price leaves unused then sits to the left of the coin — where it reads as
/// the menu bar's own spacing — instead of after the change, where it read as
/// a gap between the number and the end of the item.
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
        /// The same change as a number, which is what picks its colour.
        let changeValue: Double
    }

    /// The colour of the coin and the price, or nil to keep the template.
    ///
    /// A template image takes the menu bar's tint and inverts with light and
    /// dark by itself, which is what "自动" means. A colour of its own gives
    /// up that adaptation on purpose: it is for a menu bar that reads as light
    /// while the system says dark, or the other way round.
    ///
    /// "随涨跌" reads the change and takes the panel's own green or red, so
    /// that the price in the menu bar and the number in the panel cannot
    /// disagree. A change with no side of its own — one that prints as
    /// "0.00%" — goes back to the template, since there is nothing to colour.
    ///
    /// This colour covers the coin and the price only. The change after them
    /// is coloured by direction whatever is chosen here — see `changeColour`.
    static func tint(_ choice: MenuBarTint, change: Double, colors: ChangeColors) -> NSColor? {
        switch choice {
        case .automatic: return nil
        case .dark: return .black
        case .light: return .white
        case .change:
            guard let green = colors.isGreen(change) else { return nil }
            return green ? .systemGreen : .systemRed
        }
    }

    /// The colour of the change, which is by direction and nothing else.
    ///
    /// The choice above says how the coin and the price should sit on the
    /// wallpaper; it has no say here. Green up and red down is the one thing
    /// in the label that carries meaning, and a menu bar that coloured it
    /// black would lose that reading for the sake of consistency.
    static func changeColour(_ change: Double, colors: ChangeColors) -> NSColor {
        guard let green = colors.isGreen(change) else { return .secondaryLabelColor }
        return green ? .systemGreen : .systemRed
    }

    /// U+2009. The separator between the currency and the number.
    private static let thinSpace = "\u{2009}"

    /// The coin, the currency and the price — the part this file draws.
    ///
    /// The change is not in here. It is set as the item's title instead, so
    /// that the menu bar colours it and the price beside it separately: the
    /// price follows the choice above, the change is always green or red.
    static func attributed(_ label: Label, colour: NSColor = .black) -> NSAttributedString {
        let smallFont = NSFont.systemFont(ofSize: 10, weight: .medium)
        let digitsFont = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)

        let text = NSMutableAttributedString(
            string: label.coin + " ",
            attributes: [.font: smallFont, .foregroundColor: colour]
        )
        text.append(NSAttributedString(
            string: label.symbol,
            attributes: [.font: smallFont, .foregroundColor: colour]
        ))
        // A thin space, not a full one: the symbol is a size down already, and
        // a full space at the digits' size opens a gap wide enough to read as
        // a gap rather than as the symbol belonging to the number.
        text.append(NSAttributedString(
            string: thinSpace + label.amount,
            attributes: [.font: digitsFont, .foregroundColor: colour]
        ))
        return text
    }

    /// The change as the item's title: the menu bar sets this text itself, in
    /// the colour given here, so green and red survive any choice above.
    ///
    /// `opacity` is how the change joins a scroll: it cannot ride one — a
    /// title sits on a single line — so it fades out with the old coin and in
    /// with the new one instead.
    static func changeTitle(
        _ label: Label,
        colors: ChangeColors,
        opacity: CGFloat = 1
    ) -> NSAttributedString {
        let font = NSFont.systemFont(ofSize: 10, weight: .medium)
        let shown = label.change.isEmpty ? widthReserve(label.changeValue) : label.change
        // No space before the change: the item leaves a fixed gap between the
        // image and the title, and a space on top of it would grow that gap
        // with the font rather than keep it the same for every coin.
        return NSAttributedString(
            string: shown,
            attributes: [
                .font: font,
                .foregroundColor: changeColour(label.changeValue, colors: colors)
                    .withAlphaComponent(opacity),
            ]
        )
    }

    /// The room the change takes as the item's title, the same for every coin:
    /// the wider of a full-width sample and whatever this one prints.
    static func changeWidth(_ change: Double) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 10, weight: .medium)
        return ceil(widthReserve(change).size(withAttributes: [.font: font]).width)
    }

    /// The width the price is drawn into, so that the whole item keeps one
    /// width whatever coin is showing.
    ///
    /// It is the widest price, plus the room this coin's change does not need.
    /// The price is drawn against the right edge of it, so both the price and
    /// the change beside it hold still, and the slack ends up on the far left
    /// of the label — before the coin, where the menu bar already has a gap of
    /// its own — rather than between the "%" and the end of the item.
    static func canvasWidth(change: CGFloat, widestPrice: CGFloat, widestChange: CGFloat) -> CGFloat {
        widestPrice + max(0, widestChange - change)
    }

    /// How wide the drawn part of this coin's label would be, on its own.
    static func width(of label: Label) -> CGFloat {
        ceil(attributed(label).size().width)
    }

    /// The change text to measure the item's width against.
    ///
    /// A change that rounds to nothing prints as nothing, and a label that
    /// loses forty points the moment a coin crosses flat would shift every
    /// icon beside it. So an empty change is measured as if it were there.
    ///
    /// The title is not drawn here, so this width no longer feeds the image.
    /// It measures the room the change takes as a title, which the panel's
    /// preview and the item's own width are written against.
    static func widthReserve(_ change: Double) -> String {
        let text = formatArrowed(change)
        return text.isEmpty ? "▲00.00%" : text
    }

    /// `width` is the room the label has: the widest label of the coins the
    /// menu bar shows, so that the item never changes size between them. The
    /// price is drawn against its right edge, which keeps it and the change
    /// beside it in one place while the slack sits out of sight on the left.
    static func image(_ label: Label, width: CGFloat, tint: NSColor? = nil) -> NSImage {
        let text = attributed(label, colour: tint ?? .black)
        let size = text.size()
        let canvas = NSSize(width: contentWidth(text, width), height: ceil(size.height))
        let image = NSImage(size: canvas, flipped: false) { _ in
            text.draw(at: NSPoint(x: rightEdge(of: text, in: canvas), y: 0))
            return true
        }
        image.isTemplate = tint == nil
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
        progress: CGFloat,
        tint: NSColor? = nil
    ) -> NSImage {
        let colour = tint ?? .black
        let out = attributed(old, colour: colour)
        let into = attributed(new, colour: colour)
        let lift = ceil(max(out.size().height, into.size().height))
        let canvas = NSSize(
            width: contentWidth(out.size().width > into.size().width ? out : into, width),
            height: lift
        )

        let image = NSImage(size: canvas, flipped: false) { _ in
            let travel = progress * lift
            // The old label leaves upward, the new one follows it into the
            // space it is leaving, so the two are always exactly one apart.
            out.draw(at: NSPoint(x: rightEdge(of: out, in: canvas), y: travel))
            into.draw(at: NSPoint(x: rightEdge(of: into, in: canvas), y: travel - lift))
            return true
        }
        image.isTemplate = tint == nil
        return image
    }

    /// The label the menu bar is showing now, or nil before the first price.
    @MainActor static func label(for store: Store) -> Label? {
        guard let quote = store.menuBarQuote else { return nil }
        return Label(
            coin: quote.coin,
            symbol: store.currency.symbol,
            amount: store.amount(quote.price),
            change: formatArrowed(quote.change),
            changeValue: quote.change
        )
    }

    @MainActor static func tint(for store: Store) -> NSColor? {
        tint(
            store.menuBarTint,
            change: store.menuBarQuote?.change ?? 0,
            colors: store.changeColors
        )
    }

    @MainActor static func image(for store: Store) -> NSImage? {
        guard let label = label(for: store) else { return nil }
        return image(label, width: width(of: label), tint: tint(for: store))
    }

    /// The change the item is showing now, ready to be its title.
    @MainActor static func changeTitle(for store: Store) -> NSAttributedString {
        guard let label = label(for: store) else { return NSAttributedString(string: "") }
        return changeTitle(label, colors: store.changeColors)
    }

    /// Half a point of headroom on the left: the glyphs of a font's bounding
    /// box can be a hair wider than the box it reports, and a clipped edge is
    /// visible at this size.
    private static func contentWidth(_ text: NSAttributedString, _ width: CGFloat) -> CGFloat {
        max(width, ceil(text.size().width)) + 1
    }

    /// Where a line of text starts so that it ends half a point short of the
    /// canvas' right edge.
    private static func rightEdge(of text: NSAttributedString, in canvas: NSSize) -> CGFloat {
        max(0.5, canvas.width - ceil(text.size().width) - 0.5)
    }
}
