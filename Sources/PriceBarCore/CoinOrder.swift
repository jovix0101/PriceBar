import Foundation

/// The coins, in the one order both the panel and the menu bar use.
///
/// Kept here rather than in the store so that the rules can be checked: an
/// unticked coin leaves the menu bar without leaving the panel, a coin taken
/// off the panel leaves the menu bar too, and a dragged coin lands where it
/// was dropped in both places.
public enum CoinOrder {
    /// The menu bar's list after ticking or unticking `coin`.
    ///
    /// Adding keeps the panel's order rather than the order of ticking, so
    /// that the menu bar reads the same way the panel does.
    public static func toggling(_ coin: String, panel: [String], menuBar: [String]) -> [String] {
        if menuBar.contains(coin) {
            return menuBar.filter { $0 != coin }
        }
        return panel.filter { $0 == coin || menuBar.contains($0) }
    }

    /// The list against the panel as it now stands: a coin removed from the
    /// panel is removed here too, and the rest follow the panel's order.
    ///
    /// Putting the survivors in panel order is what makes dragging a coin in
    /// the settings window move it in the menu bar as well: there is one
    /// order, and the menu bar shows the part of it that is ticked.
    ///
    /// Unticking the last coin is allowed and leaves the list empty. The menu
    /// bar then falls back to the panel's first price, which the settings
    /// window says in words — a control that refuses the click without saying
    /// why reads as broken.
    public static func settled(_ menuBar: [String], panel: [String]) -> [String] {
        panel.filter { menuBar.contains($0) }
    }

    /// `coins` with `coin` dropped onto `target`: in front of it when dragged
    /// up the list, behind it when dragged down.
    ///
    /// Landing on the row it was dropped on, rather than always in front of
    /// it, is what lets two coins change places: "always in front" leaves a
    /// coin dragged onto the row below it exactly where it was, and with only
    /// two coins there is no other row to aim at.
    ///
    /// A coin dropped on itself, or on a coin that is not in the list, leaves
    /// the list as it was: dragging past the end should not lose the thing
    /// being dragged.
    public static func moving(_ coin: String, onto target: String, in coins: [String]) -> [String] {
        guard coin != target,
              let from = coins.firstIndex(of: coin),
              let to = coins.firstIndex(of: target)
        else { return coins }

        var out = coins
        out.remove(at: from)
        // `to` was counted on the longer list. Taking out a coin above the
        // target pulls the target up by one, which is exactly where the
        // dropped coin has to go to land behind it; a coin from below leaves
        // the target where it was, and that index puts the dropped coin in
        // front of it. One number, both directions.
        out.insert(coin, at: min(to, out.count))
        return out
    }
}
