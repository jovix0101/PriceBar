import Foundation

/// One coin's price as the app shows it.
public struct Quote: Identifiable, Equatable, Sendable {
    public var id: String { coin }
    public let coin: String
    public let price: Double   // in USD
    public let change: Double  // 24h change, percent

    public init(coin: String, price: Double, change: Double) {
        self.coin = coin
        self.price = price
        self.change = change
    }
}

/// What a rule watches.
public enum Metric: String, Codable, CaseIterable, Sendable {
    /// The price itself, always in USD.
    case price
    /// The 24h change, in percent.
    case change

    public func label(_ strings: Strings) -> String {
        strings.label(self)
    }

    /// What a threshold of this metric counts, for the field that sets it.
    public var unit: String {
        switch self {
        case .price: "USD"
        case .change: "%"
        }
    }
}

/// A rule that notifies when a value crosses a threshold.
///
/// A rule watches the quote itself, which the exchange quotes in US dollars,
/// so `threshold` is in US dollars whatever currency the panel shows. The
/// panel may show yuan, but a threshold set at 80000 means $80,000 and stays
/// that meaning when the currency changes.
public struct Rule: Identifiable, Codable, Equatable, Sendable {
    public var id = UUID()
    public var coin: String
    public var metric: Metric
    /// True when the rule fires above the threshold, false when below.
    public var above: Bool
    /// A price in US dollars, or a percentage: -5 is a 5% fall. Never in the
    /// currency the panel shows.
    public var threshold: Double
    /// False once the rule has fired, until the value returns to the other
    /// side of the threshold: a price that sits on it notifies once.
    public var armed = true

    public init(coin: String, metric: Metric, above: Bool, threshold: Double) {
        self.coin = coin
        self.metric = metric
        self.above = above
        self.threshold = threshold
    }

    /// The value the rule watches in a quote.
    public func value(of quote: Quote) -> Double? {
        switch metric {
        case .price: quote.price
        case .change: quote.change
        }
    }

    /// How far past the threshold the value must return before the rule
    /// arms again: 0.3% of a price, 0.2 points of a change. Without it, a
    /// value resting on the threshold would notify on every refresh.
    public var hysteresis: Double {
        switch metric {
        case .price: abs(threshold) * 0.003
        case .change: 0.2
        }
    }

    /// The threshold as the user reads it: "$80000", "5%".
    public var thresholdText: String {
        switch metric {
        case .price: formatMoney(threshold, currency: .usd)
        case .change: formatPercent(threshold)
        }
    }
}
