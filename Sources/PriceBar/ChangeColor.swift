import SwiftUI
import PriceBarCore

/// The colors a movement is drawn in.
///
/// Kept out of `Store`, which knows nothing of SwiftUI: the store holds the
/// choice, and the views turn it into a color. The line and the percentage
/// both ask here, so that the two never disagree.
extension ChangeColors {
    func color(for change: Double) -> Color {
        guard let green = isGreen(change) else { return .secondary }
        return Color(nsColor: green ? .systemGreen : .systemRed)
    }
}
