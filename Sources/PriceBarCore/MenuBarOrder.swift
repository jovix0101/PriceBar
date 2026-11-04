import Foundation

/// Which coins the menu bar takes turns showing.
///
/// Kept here rather than in the view so that the rule can be checked: the
/// turns follow the panel's order, and a coin taken off the panel takes its
/// turn with it.
public enum MenuBarOrder {
    /// The menu bar's list after ticking or unticking `coin`.
    ///
    /// Adding keeps the panel's order rather than the order of ticking, so
    /// that the turns read the same way the list does.
    public static func toggling(_ coin: String, panel: [String], menuBar: [String]) -> [String] {
        if menuBar.contains(coin) {
            return menuBar.filter { $0 != coin }
        }
        return panel.filter { $0 == coin || menuBar.contains($0) }
    }

    /// The list as it stands against the panel: a coin removed from the panel
    /// is removed here too.
    ///
    /// Unticking the last coin is allowed and leaves the list empty. The menu
    /// bar then falls back to the panel's first price, which the settings
    /// window says in words — a control that refuses the click without saying
    /// why reads as broken.
    public static func settled(_ menuBar: [String], panel: [String]) -> [String] {
        menuBar.filter { panel.contains($0) }
    }
}
