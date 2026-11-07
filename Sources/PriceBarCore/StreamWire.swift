import Foundation

/// How one exchange pushes prices over one connection: where to connect,
/// what to say once there, and what to send so the far end keeps it open.
///
/// Each exchange speaks its own dialect, checked against the live servers:
///
/// - Binance names the streams in the address and needs nothing sent.
///   Contracts need the routed `/market` path: the old `/ws` path accepts
///   the connection and then sends nothing.
/// - Gate subscribes per channel and fails a whole spot subscription over
///   one unknown pair, so every coin is asked for on its own. It answers
///   `spot.ping` / `futures.ping`.
/// - OKX serves spot and contracts on one connection, fails only the unknown
///   instrument of a subscription, drops a connection that is quiet for 30
///   seconds and answers a plain `ping`. Only port 443 gets through.
/// - Bybit fails a whole subscription over one unknown symbol, so every coin
///   is asked for on its own. It wants `{"op":"ping"}` every 20 seconds.
struct StreamWire: Sendable, Equatable {
    /// The connection's name among the source's others: the market it
    /// carries, or "all" where one connection carries both.
    let key: String
    let source: MarketSource
    let url: URL
    let instruments: [Instrument]

    /// The ids of the instruments it carries, which go live and drop together.
    var ids: Set<String> { Set(instruments.map(\.id)) }

    /// What to send once the connection is open.
    func subscriptions(at now: Date) -> [String] {
        let time = Int(now.timeIntervalSince1970)
        switch source {
        case .binance:
            return []
        case .gate:
            let channel = key == Market.spot.rawValue ? "spot.tickers" : "futures.tickers"
            return instruments.map { instrument in
                #"{"time":\#(time),"channel":"\#(channel)","event":"subscribe","payload":["\#(source.symbol(for: instrument))"]}"#
            }
        case .okx:
            let args = instruments
                .map { #"{"channel":"tickers","instId":"\#(source.symbol(for: $0))"}"# }
                .joined(separator: ",")
            return [#"{"op":"subscribe","args":[\#(args)]}"#]
        case .bybit:
            return instruments.map { #"{"op":"subscribe","args":["tickers.\#(source.symbol(for: $0))"]}"# }
        }
    }

    /// What to send now and then so the exchange keeps a quiet connection
    /// open. Its answer also tells that the far end is still there. Binance
    /// needs none: the WebSocket's own ping does.
    func heartbeat(at now: Date) -> String? {
        switch source {
        case .binance:
            return nil
        case .gate:
            let channel = key == Market.spot.rawValue ? "spot.ping" : "futures.ping"
            return #"{"time":\#(Int(now.timeIntervalSince1970)),"channel":"\#(channel)"}"#
        case .okx:
            return "ping"
        case .bybit:
            return #"{"op":"ping"}"#
        }
    }
}

extension MarketSource {
    /// The connections that push these instruments' prices, one per market,
    /// or one in all where the exchange carries both on one.
    func streamWires(for instruments: [Instrument]) -> [StreamWire] {
        if self == .okx {
            guard !instruments.isEmpty,
                  let url = URL(string: "wss://ws.okx.com/ws/v5/public") else { return [] }
            return [StreamWire(key: "all", source: self, url: url, instruments: instruments)]
        }
        return Market.allCases.compactMap { market in
            let group = instruments.filter { $0.market == market }
            guard !group.isEmpty, let url = streamURL(market: market, instruments: group) else { return nil }
            return StreamWire(key: market.rawValue, source: self, url: url, instruments: group)
        }
    }

    private func streamURL(market: Market, instruments: [Instrument]) -> URL? {
        let address: String
        switch (self, market) {
        case (.binance, _):
            let base = market == .spot
                ? "wss://data-stream.binance.vision/stream?streams="
                : "wss://fstream.binance.com/market/stream?streams="
            let streams = instruments.map { symbol(for: $0).lowercased() + "@ticker" }
            address = base + streams.joined(separator: "/")
        case (.gate, .spot): address = "wss://api.gateio.ws/ws/v4/"
        case (.gate, .perpetual): address = "wss://fx-ws.gateio.ws/v4/ws/usdt"
        case (.okx, _): address = "wss://ws.okx.com/ws/v5/public"
        case (.bybit, .spot): address = "wss://stream.bybit.com/v5/public/spot"
        case (.bybit, .perpetual): address = "wss://stream.bybit.com/v5/public/linear"
        }
        return URL(string: address)
    }
}

/// Reads the prices out of one connection's messages.
///
/// A reader lives as long as its connection: Bybit's contracts send a full
/// ticker once and then only the fields that changed, so the reader keeps
/// the last full one to fill the rest in.
struct StreamReader {
    private let source: MarketSource
    /// The exchange's symbol, upper-cased, to the instrument asked for.
    private let watching: [String: String]
    private var last: [String: (price: Double?, change: Double?)] = [:]

    init(wire: StreamWire) {
        source = wire.source
        watching = Dictionary(
            wire.instruments.map { (wire.source.symbol(for: $0).uppercased(), $0.id) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// The prices in one message: none for acknowledgements, pongs and
    /// anything else that is not a usable price of a watched instrument.
    mutating func quotes(in text: String) -> [Quote] {
        guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        else { return [] }
        switch source {
        case .binance:
            guard let data = object["data"] as? [String: Any] else { return [] }
            return quote(symbol: data["s"], price: data["c"], change: number(data["P"])).map { [$0] } ?? []
        case .gate:
            guard object["event"] as? String == "update" else { return [] }
            let rows = (object["result"] as? [[String: Any]])
                ?? (object["result"] as? [String: Any]).map { [$0] } ?? []
            return rows.compactMap { row in
                quote(symbol: row["currency_pair"] ?? row["contract"], price: row["last"],
                      change: number(row["change_percentage"]))
            }
        case .okx:
            let rows = object["data"] as? [[String: Any]] ?? []
            return rows.compactMap { row in
                let open = number(row["open24h"]) ?? 0
                let price = number(row["last"]) ?? 0
                return quote(symbol: row["instId"], price: row["last"],
                             change: open > 0 ? (price / open - 1) * 100 : 0)
            }
        case .bybit:
            guard let data = object["data"] as? [String: Any],
                  let symbol = (data["symbol"] as? String)?.uppercased(),
                  watching[symbol] != nil
            else { return [] }
            var known: (price: Double?, change: Double?) = (nil, nil)
            if object["type"] as? String != "snapshot", let kept = last[symbol] { known = kept }
            if let price = number(data["lastPrice"]) { known.price = price }
            if let fraction = number(data["price24hPcnt"]) { known.change = fraction * 100 }
            last[symbol] = known
            guard let price = known.price else { return [] }
            return quote(symbol: symbol, price: price, change: known.change).map { [$0] } ?? []
        }
    }

    private func quote(symbol: Any?, price: Any?, change: Double?) -> Quote? {
        guard let symbol = (symbol as? String)?.uppercased(),
              let coin = watching[symbol],
              let price = number(price), price.isFinite, price > 0
        else { return nil }
        let change = change.flatMap { $0.isFinite ? $0 : nil } ?? 0
        return Quote(coin: coin, price: price, change: change)
    }

    /// The exchanges send numbers as strings, but not always.
    private func number(_ value: Any?) -> Double? {
        switch value {
        case let text as String: Double(text)
        case let number as NSNumber: number.doubleValue
        default: nil
        }
    }
}
