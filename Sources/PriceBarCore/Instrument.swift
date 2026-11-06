import Foundation

/// Which market of an exchange a price is read from.
///
/// Coins trade on both. Stocks and metals trade only as contracts: the
/// exchanges list gold, silver, Apple and the rest as USDT perpetuals and
/// have no spot market for them at all.
public enum Market: String, Codable, CaseIterable, Sendable {
    /// The coin itself, against USDT.
    case spot
    /// The USDT-margined perpetual contract: no expiry, settled in USDT.
    /// Coin-margined perpetuals, contracts that expire, and pairs against
    /// other stablecoins are left out — the same coin twenty times over, a
    /// few dollars apart, is a list nobody can read.
    case perpetual

    /// The short name the panel and the settings put beside a contract,
    /// through the words of the language in hand.
    public func label(_ strings: Strings) -> String {
        strings.shortLabel(self)
    }
}

/// One thing the panel lists: a code, and the market it is read from.
///
/// Written down as one string, the way charting sites write it: "BTC" is the
/// coin on the spot market, "BTC.P" its perpetual. A string keeps every
/// place that already names a coin by its code — the order, the menu bar's
/// ticks, the alert rules — working unchanged, and a settings file written
/// before contracts existed reads as spot, which is what it always was.
public struct Instrument: Hashable, Sendable {
    /// The exchange's code for the asset: "BTC", "XAU", "AAPL".
    public let code: String
    public let market: Market

    private static let perpetualSuffix = ".P"

    public init(code: String, market: Market) {
        self.code = code.uppercased()
        self.market = market
    }

    /// Reads the stored form back: "BTC.P" is a perpetual, anything else spot.
    public init(id: String) {
        let upper = id.uppercased()
        if upper.hasSuffix(Self.perpetualSuffix) {
            self.init(code: String(upper.dropLast(Self.perpetualSuffix.count)), market: .perpetual)
        } else {
            self.init(code: upper, market: .spot)
        }
    }

    /// How a sentence names it: "BTC", or "BTC Perp". Where there is room
    /// for a tag, the views draw the market smaller instead.
    public func name(_ strings: Strings) -> String {
        market == .perpetual ? "\(code) \(market.label(strings))" : code
    }

    /// The stored form: the code, with ".P" after it for a perpetual.
    public var id: String {
        market == .perpetual ? code + Self.perpetualSuffix : code
    }
}
