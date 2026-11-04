import Foundation

/// An exchange the prices can come from.
///
/// The exchanges quote the same coin at slightly different prices — a few
/// dollars apart at any moment — so switching source moves the numbers by a
/// little. The app reads one exchange at a time and never swaps to another
/// behind the user's back: a price that changes exchange on its own would
/// look like a price that changed.
///
/// Only exchanges that quote in USDT are here. Coinbase and Kraken quote in
/// dollars, and reading one coin in a mix of USDT and USD pairs would make
/// the 24h change mean something different from row to row.
public enum MarketSource: String, Codable, CaseIterable, Sendable {
    case binance
    case gate
    case okx
    case bybit

    public var label: String {
        switch self {
        case .binance: "Binance"
        case .gate: "Gate"
        case .okx: "OKX"
        case .bybit: "Bybit"
        }
    }

    /// Whether the exchange was unreachable without a proxy from the network
    /// this was written on. The setting still lets any source go through a
    /// proxy: the check lives in `ProxySettings`, not here.
    public var normallyNeedsProxy: Bool {
        switch self {
        case .binance, .gate: false
        case .okx, .bybit: true
        }
    }

    /// The pair the exchange names this coin by. Every exchange writes the
    /// same pair differently, which is the whole reason this lives here.
    public func pair(for coin: String) -> String {
        let upper = coin.uppercased()
        switch self {
        case .binance, .bybit: return upper + "USDT"
        case .gate: return upper + "_USDT"
        case .okx: return upper + "-USDT"
        }
    }

    /// The hosts serving this exchange, tried in order. Binance keeps a host
    /// for public data alone, which some networks reach when they refuse the
    /// trading host.
    var hosts: [String] {
        switch self {
        case .binance: ["https://data-api.binance.vision", "https://api.binance.com"]
        case .gate: ["https://api.gateio.ws"]
        case .okx: ["https://www.okx.com"]
        case .bybit: ["https://api.bybit.com"]
        }
    }

    /// Whether the exchange answers for many coins at once. Only Binance
    /// does; the others take one request per coin, made side by side.
    var answersManyCoinsAtOnce: Bool {
        self == .binance
    }
}
