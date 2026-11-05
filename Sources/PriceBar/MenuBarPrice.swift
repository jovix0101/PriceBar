import AppKit
import PriceBarCore

/// The label in the menu bar: one block per coin, side by side.
///
/// Text, not an image. While the item took turns, the coin had to be drawn at
/// a fixed width so that nothing moved mid-turn, and a fixed-width drawing is
/// an image — the menu bar will not pad a title. Nothing takes turns now, so
/// the label is the title itself: the menu bar's own font, its own colour for
/// "自动" (a text run left without a colour is drawn in whatever the menu bar
/// is using, which is the one thing a drawn image could not do), and one
/// baseline for everything on it.
///
/// A block is the coin, the currency a size down, the price, and the change.
/// The change is padded to one width across all the coins, so that a coin
/// that turns flat does not pull the next one inwards. The padding is a kern
/// on the block's last glyph: an attributed title measures it, and it draws
/// nothing. A run of spaces would not do — the menu bar trims the whitespace
/// it is given and draws nothing in its place.
enum MenuBarPrice {
    /// One coin's label: the coin on the left, the currency a size down, then
    /// the price and the change.
    struct Label: Equatable {
        let coin: String
        let symbol: String
        let amount: String
        /// The 24h change after the price, arrow and all: "▲2.02%".
        let change: String
        /// The same change as a number, which is what picks its colour.
        let changeValue: Double
    }

    /// The colour of the coin and the price, or nil to leave it to the menu bar.
    ///
    /// A run left without a colour is drawn in the menu bar's own label colour
    /// and follows light and dark by itself, which is what "自动" means. A
    /// colour of its own gives up that adaptation on purpose: it is for a menu
    /// bar that reads as light while the system says dark, or the other way
    /// round.
    ///
    /// "随涨跌" reads the change and takes the panel's own green or red, so
    /// that the price in the menu bar and the number in the panel cannot
    /// disagree. A change with no side of its own — one that prints as "0%" —
    /// has nothing to colour, so the menu bar's colour comes back.
    ///
    /// This colour covers the coin and the price only. The change after them
    /// is coloured by direction whatever is chosen here — see `changeColour`.
    static func tint(_ choice: MenuBarTint, change: Double, colors: ChangeColors) -> NSColor? {
        switch choice {
        case .automatic: return nil
        case .dark: return .black
        case .light: return .white
        case .change:
            return colors.nsColour(for: change)
        }
    }

    /// The colour of the change, which is by direction and nothing else.
    ///
    /// The choice above says how the coin and the price should sit on the
    /// wallpaper; it has no say here. Green up and red down is the one thing
    /// in the label that carries meaning, and a menu bar that coloured it
    /// black would lose that reading for the sake of consistency.
    static func changeColour(_ change: Double, colors: ChangeColors) -> NSColor {
        colors.nsColour(for: change) ?? .secondaryLabelColor
    }

    /// The whole label: every coin's block, each padded to one width.
    static func title(
        _ labels: [Label],
        choice: MenuBarTint,
        colors: ChangeColors
    ) -> NSAttributedString {
        guard !labels.isEmpty else { return NSAttributedString(string: "—") }

        // The change blocks are all the same width, so the width has to be
        // known before the first one is set.
        let heads = labels.map { head($0) }
        let changes = labels.map { change($0, colors: colors) }
        let changeWidth = max(
            changes.map { ceil($0.size().width) }.max() ?? 0,
            roomForChange()
        )

        let out = NSMutableAttributedString()
        for index in labels.indices {
            if index > 0 { out.append(gap) }

            let head = NSMutableAttributedString(attributedString: heads[index])
            if let colour = tint(choice, change: labels[index].changeValue, colors: colors) {
                head.addAttribute(
                    .foregroundColor,
                    value: colour,
                    range: NSRange(location: 0, length: head.length)
                )
            }
            out.append(head)

            let change = NSMutableAttributedString(attributedString: changes[index])
            pad(change, to: changeWidth)
            out.append(change)
        }
        return out
    }

    /// The label as a screen reader, or a tooltip, should read it.
    static func reading(_ labels: [Label]) -> String {
        labels
            .map { "\($0.coin) \($0.symbol)\($0.amount) \($0.change)" }
            .joined(separator: "，")
            .trimmingCharacters(in: .whitespaces)
    }

    /// U+2009. The separator between the currency and the number.
    ///
    /// A thin space, not a full one: the symbol is a size down already, and a
    /// full space at the digits' size opens a gap wide enough to read as a gap
    /// rather than as the symbol belonging to the number.
    private static let thinSpace = "\u{2009}"

    private static func head(_ label: Label) -> NSAttributedString {
        let text = NSMutableAttributedString(
            string: label.coin + " ",
            attributes: [.font: smallFont]
        )
        text.append(NSAttributedString(string: label.symbol, attributes: [.font: smallFont]))
        text.append(NSAttributedString(
            string: thinSpace + label.amount,
            attributes: [.font: digitsFont]
        ))
        return text
    }

    /// The change in its own colour, with the space that keeps it off the price.
    private static func change(_ label: Label, colors: ChangeColors) -> NSAttributedString {
        NSAttributedString(
            string: " " + label.change,
            attributes: [
                .font: smallFont,
                .foregroundColor: changeColour(label.changeValue, colors: colors),
            ]
        )
    }

    /// The gap between two coins: wider than the gap inside a block, so that
    /// the blocks read as separate prices rather than as one long line.
    private static var gap: NSAttributedString {
        NSAttributedString(string: " ", attributes: [.font: smallFont, .kern: 11])
    }

    /// Grows `text` to `width` with a kern on its last glyph, if it is short.
    ///
    /// A kern is the only padding a title draws: it is measured, and it puts
    /// no glyph on the screen.
    private static func pad(_ text: NSMutableAttributedString, to width: CGFloat) {
        let shortfall = width - ceil(text.size().width)
        guard shortfall > 0.5, text.length > 0 else { return }
        let last = NSRange(location: text.length - 1, length: 1)
        let existing = text.attribute(.kern, at: last.location, effectiveRange: nil) as? CGFloat ?? 0
        text.addAttribute(.kern, value: existing + shortfall, range: last)
    }

    private static var smallFont: NSFont {
        NSFont.systemFont(ofSize: 10, weight: .medium)
    }

    private static var digitsFont: NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
    }

    /// The narrowest a change block is allowed to be, so that "0%" does not
    /// pull the coin after it inwards.
    private static let changeSample = "▲00.00%"

    /// How narrow the change block can ever be.
    ///
    /// Measured with the space the change is set behind, because that space is
    /// part of the block: a block measured 47 wide but holding a 50-wide
    /// string would grow the item the moment this coin moved a whole per cent.
    static func roomForChange() -> CGFloat {
        ceil(NSAttributedString(string: " " + changeSample, attributes: [.font: smallFont])
            .size().width)
    }

    // MARK: - From the store

    @MainActor static func labels(for store: Store) -> [MenuBarPrice.Label] {
        store.menuBarQuotes.map { quote in
            // The code alone, contract or not: the menu bar has no room for
            // a tag, and the panel beside it says which is which.
            Label(
                coin: Instrument(id: quote.coin).code,
                symbol: store.currency.symbol,
                amount: store.amount(quote.price),
                change: formatArrowed(quote.change),
                changeValue: quote.change
            )
        }
    }

    /// The label the menu bar is showing now, ready to be its title.
    @MainActor static func title(for store: Store) -> NSAttributedString {
        title(labels(for: store), choice: store.menuBarTint, colors: store.changeColors)
    }
}
