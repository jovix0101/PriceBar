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

    /// Whether this market of the exchange was unreachable without a proxy.
    /// Binance serves its spot prices from a host of their own that most
    /// networks reach; its contracts have no such host.
    public func normallyNeedsProxy(for market: Market) -> Bool {
        switch (self, market) {
        case (.binance, .perpetual): true
        default: normallyNeedsProxy
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

    /// The exchange's name for this instrument. A perpetual is named like
    /// the spot pair everywhere but OKX, which adds "-SWAP": the market is
    /// told apart by the address it is asked at, not by the name.
    public func symbol(for instrument: Instrument) -> String {
        let pair = pair(for: instrument.code)
        switch (self, instrument.market) {
        case (.okx, .perpetual): return pair + "-SWAP"
        default: return pair
        }
    }

    /// The exchange's own page for this coin's perpetual contract, for a
    /// reader who wants to go and look at the market the number came from.
    ///
    /// The quote in the panel is spot, the page is the contract: the two sit
    /// a fraction apart, which is how the exchange itself shows them side by
    /// side. Where the exchange has a site in the language the app is
    /// showing, it is that one: a page that answers in English reads as a
    /// different product from the one beside it.
    ///
    /// Only the shape lives here, so it can be checked without a browser.
    public func contractPage(for coin: String, language: Language = .english) -> URL? {
        let upper = coin.uppercased()
        let lower = coin.lowercased()
        let chinese = language == .chinese
        let address: String
        switch self {
        case .binance:
            address = chinese
                ? "https://www.binance.com/zh-CN/futures/\(upper)USDT"
                : "https://www.binance.com/en/futures/\(upper)USDT"
        case .gate:
            address = chinese
                ? "https://www.gate.io/zh/futures/USDT/\(upper)_USDT"
                : "https://www.gate.io/futures/USDT/\(upper)_USDT"
        case .okx:
            address = chinese
                ? "https://www.okx.com/zh-hans/trade-swap/\(lower)-usdt-swap"
                : "https://www.okx.com/trade-swap/\(lower)-usdt-swap"
        case .bybit:
            address = "https://www.bybit.com/trade/usdt/\(upper)USDT"
        }
        return URL(string: address)
    }

    /// The hosts serving one market of this exchange, tried in order.
    /// Binance keeps a host for public spot data alone, which some networks
    /// reach when they refuse the trading host, and its contracts on a host
    /// of their own.
    func hosts(for market: Market) -> [String] {
        switch (self, market) {
        case (.binance, .spot): ["https://data-api.binance.vision", "https://api.binance.com"]
        case (.binance, .perpetual): ["https://fapi.binance.com"]
        case (.gate, _): ["https://api.gateio.ws"]
        case (.okx, _): ["https://www.okx.com"]
        case (.bybit, _): ["https://api.bybit.com"]
        }
    }

    /// Whether the exchange answers for many coins at once. Only Binance
    /// does, and only on its spot market; everything else takes one request
    /// per coin, made side by side.
    func answersManyAtOnce(on market: Market) -> Bool {
        self == .binance && market == .spot
    }
}
