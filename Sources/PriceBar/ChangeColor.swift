import SwiftUI
import PriceBarCore

/// The colors a movement is drawn in.
///
/// Kept out of `Store`, which knows nothing of SwiftUI: the store holds the
/// choice, and the views turn it into a color. The line and the percentage
/// both ask here, so that the two never disagree.
extension ChangeColors {
    func color(for change: Double) -> Color {
        guard change != 0 else { return .secondary }
        let up = change > 0
        switch self {
        case .greenUp: return Color(nsColor: up ? .systemGreen : .systemRed)
        case .redUp: return Color(nsColor: up ? .systemRed : .systemGreen)
        }
    }
}
