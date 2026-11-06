import SwiftUI

/// A day of prices as a line: the shape of the move, in the space a word
/// takes up.
///
/// Drawn as a line rather than an area so that it reads as a trend and not as
/// a value — the number beside it is the value.
struct Sparkline: View {
    let values: [Double]
    /// The color of the movement, chosen by the caller: the line and the
    /// percentage beside it must agree.
    let color: Color

    static let width: CGFloat = 44
    static let height: CGFloat = 16

    var body: some View {
        Line(values: values)
            .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            .frame(width: Self.width, height: Self.height)
            // The row reads the change out loud already; a second reading of
            // the same movement would only be noise.
            .accessibilityHidden(true)
    }

}

private struct Line: Shape {
    let values: [Double]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard values.count > 1,
              let lowest = values.min(),
              let highest = values.max() else { return path }

        // Half the stroke would be clipped by the frame without this.
        let inner = rect.insetBy(dx: 0.75, dy: 0.75)
        let span = highest - lowest

        for (index, value) in values.enumerated() {
            let progress = Double(index) / Double(values.count - 1)
            let ratio = span > 0 ? (value - lowest) / span : 0.5
            let point = CGPoint(
                x: inner.minX + inner.width * progress,
                y: inner.maxY - inner.height * ratio
            )
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        return path
    }
}

#Preview("Line") {
    VStack(alignment: .leading, spacing: 8) {
        Sparkline(values: (0..<24).map { 100 + sin(Double($0) / 3) * 6 + Double($0) }, color: .green)
        Sparkline(values: (0..<24).map { 100 - Double($0) * 1.5 }, color: .red)
        Sparkline(values: Array(repeating: 100.0, count: 24), color: .secondary)
    }
    .padding()
}
