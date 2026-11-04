import Foundation

/// Reads prices and the shape of the day from an exchange.
///
/// Each exchange answers in its own shape: its own spelling of the pair, its
/// own field names, its own order of candles. One parser per exchange, each
/// tested against a captured response, is the only way to read four of them
/// without reading none of them correctly.
public enum PriceAPI {
    // MARK: - Quotes

    /// Fetches every coin's quote from the exchange, in the order of coins.
    /// Coins the exchange does not know are left out.
    public static func quotes(
        for coins: [String],
        source: MarketSource = .binance,
        session: URLSession = .shared
    ) async throws -> [Quote] {
        let wanted = coins.map { $0.uppercased() }
        guard !wanted.isEmpty else { return [] }

        if source.answersManyCoinsAtOnce {
            return try await binanceQuotes(for: wanted, session: session)
        }
        return try await oneByOne(wanted, source: source, session: session)
    }

    /// What one child of the task group below came back with.
    ///
    /// A tuple would read the same, but the release optimiser drops the
    /// `for await` body when the element type is a tuple of optionals: the
    /// loop then runs zero times and every quote is lost. A named enum keeps
    /// the loop, and says what each case means.
    private enum Outcome: Sendable {
        case got(coin: String, quote: Quote)
        case failed(coin: String, message: String)
    }

    /// Reads one coin per request, side by side, and keeps the order the
    /// coins were asked for. A coin the exchange does not list is left out —
    /// one unknown symbol should not cost the others their price.
    private static func oneByOne(
        _ coins: [String],
        source: MarketSource,
        session: URLSession
    ) async throws -> [Quote] {
        var found: [String: Quote] = [:]
        var lastMessage: String?

        await withTaskGroup(of: Outcome.self) { group in
            for coin in coins {
                group.addTask {
                    do {
                        return .got(coin: coin, quote: try await quote(coin: coin, source: source, session: session))
                    } catch {
                        return .failed(coin: coin, message: error.localizedDescription)
                    }
                }
            }
            for await outcome in group {
                switch outcome {
                case let .got(coin, quote):
                    found[coin] = quote
                case let .failed(_, message):
                    lastMessage = message
                }
            }
        }

        guard !found.isEmpty else {
            throw PriceError.unreachable(
                lastMessage ?? PriceError.noData.localizedDescription
            )
        }
        return coins.compactMap { found[$0] }
    }

    /// One coin, trying the exchange's hosts in turn.
    private static func quote(coin: String, source: MarketSource, session: URLSession) async throws -> Quote {
        var lastError: Error = PriceError.noData
        for host in source.hosts {
            guard let url = tickerURL(source: source, coin: coin, host: host) else { continue }
            do {
                let (data, response) = try await session.data(from: url)
                if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                    lastError = PriceError.badResponse(http.statusCode)
                    continue
                }
                if let quote = self.quote(from: data, source: source, coin: coin) {
                    return quote
                }
                lastError = PriceError.noData
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private static func tickerURL(source: MarketSource, coin: String, host: String) -> URL? {
        let pair = source.pair(for: coin)
        var components: URLComponents?
        switch source {
        case .binance:
            components = URLComponents(string: host + "/api/v3/ticker/24hr")
            components?.queryItems = [URLQueryItem(name: "symbol", value: pair)]
        case .gate:
            components = URLComponents(string: host + "/api/v4/spot/tickers")
            components?.queryItems = [URLQueryItem(name: "currency_pair", value: pair)]
        case .okx:
            components = URLComponents(string: host + "/api/v5/market/ticker")
            components?.queryItems = [URLQueryItem(name: "instId", value: pair)]
        case .bybit:
            components = URLComponents(string: host + "/v5/market/tickers")
            components?.queryItems = [
                URLQueryItem(name: "category", value: "spot"),
                URLQueryItem(name: "symbol", value: pair),
            ]
        }
        return components?.url
    }

    // MARK: - Each exchange's answer

    private struct BinanceTicker: Decodable {
        let symbol: String
        let lastPrice: String
        let priceChangePercent: String
    }

    /// Binance is the one exchange that answers for many pairs at once: one
    /// request for the whole panel. A single symbol comes back as an object,
    /// a list of them as an array.
    private static func binanceQuotes(for coins: [String], session: URLSession) async throws -> [Quote] {
        var lastError: Error = PriceError.noData

        for host in MarketSource.binance.hosts {
            guard var components = URLComponents(string: host + "/api/v3/ticker/24hr") else { continue }
            if coins.count == 1 {
                components.queryItems = [
                    URLQueryItem(name: "symbol", value: MarketSource.binance.pair(for: coins[0])),
                ]
            } else {
                // The list has to be percent-encoded by hand: the query is
                // read as already-encoded by URLComponents, and a pair of
                // brackets left as they are is a request for nothing.
                let list = try? JSONSerialization.data(withJSONObject: coins.map { $0 + "USDT" })
                let encoded = list
                    .flatMap { String(data: $0, encoding: .utf8) }?
                    .addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "[]"
                components.percentEncodedQuery = "symbols=" + encoded
            }
            guard let url = components.url else { continue }

            do {
                let (data, response) = try await session.data(from: url)
                if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                    lastError = PriceError.badResponse(http.statusCode)
                    continue
                }
                let quotes = try binanceQuotes(from: data, coins: coins)
                if quotes.isEmpty {
                    lastError = PriceError.noData
                    continue
                }
                return quotes
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    static func binanceQuotes(from data: Data, coins: [String]) throws -> [Quote] {
        let decoder = JSONDecoder()
        let tickers: [BinanceTicker]
        if let list = try? decoder.decode([BinanceTicker].self, from: data) {
            tickers = list
        } else if let one = try? decoder.decode(BinanceTicker.self, from: data) {
            tickers = [one]
        } else {
            throw PriceError.noData
        }

        var byCoin: [String: Quote] = [:]
        for ticker in tickers {
            let coin = ticker.symbol.uppercased().replacingOccurrences(of: "USDT", with: "")
            guard let price = Double(ticker.lastPrice) else { continue }
            byCoin[coin] = Quote(
                coin: coin,
                price: price,
                change: Double(ticker.priceChangePercent) ?? 0
            )
        }
        return coins.compactMap { byCoin[$0] }
    }

    /// Gate names the pair with an underscore and spells the change as a
    /// percentage already.
    struct GateTicker: Decodable {
        let pair: String
        let last: String?
        let change: String?

        enum CodingKeys: String, CodingKey {
            case pair = "currency_pair"
            case last
            case change = "change_percentage"
        }
    }

    static func gateQuote(from data: Data, coin: String) -> Quote? {
        guard let rows = try? JSONDecoder().decode([GateTicker].self, from: data),
              let row = rows.first(where: { $0.pair.uppercased() == MarketSource.gate.pair(for: coin) }),
              let last = row.last, let price = Double(last)
        else { return nil }
        return Quote(coin: coin.uppercased(), price: price, change: Double(row.change ?? "") ?? 0)
    }

    /// OKX sends no change at all: the 24h change has to be worked out from
    /// the price 24 hours ago, which it does send.
    struct OKXResponse: Decodable {
        let code: String
        let data: [Ticker]

        struct Ticker: Decodable {
            let last: String
            let open24h: String
        }
    }

    static func okxQuote(from data: Data, coin: String) -> Quote? {
        guard let response = try? JSONDecoder().decode(OKXResponse.self, from: data),
              let ticker = response.data.first,
              let price = Double(ticker.last)
        else { return nil }
        let open = Double(ticker.open24h) ?? 0
        let change = open > 0 ? (price / open - 1) * 100 : 0
        return Quote(coin: coin.uppercased(), price: price, change: change)
    }

    /// Bybit spells the change as a fraction — -0.0034 is a fall of 0.34%.
    struct BybitResponse: Decodable {
        let retCode: Int
        let result: Result

        struct Result: Decodable {
            let list: [Ticker]
        }

        struct Ticker: Decodable {
            let lastPrice: String
            let price24hPcnt: String
        }
    }

    static func bybitQuote(from data: Data, coin: String) -> Quote? {
        guard let response = try? JSONDecoder().decode(BybitResponse.self, from: data),
              let ticker = response.result.list.first,
              let price = Double(ticker.lastPrice)
        else { return nil }
        return Quote(
            coin: coin.uppercased(),
            price: price,
            change: (Double(ticker.price24hPcnt) ?? 0) * 100
        )
    }

    /// One coin's quote, read the way its exchange writes it.
    static func quote(from data: Data, source: MarketSource, coin: String) -> Quote? {
        switch source {
        case .binance:
            return (try? binanceQuotes(from: data, coins: [coin.uppercased()]))?.first
        case .gate:
            return gateQuote(from: data, coin: coin)
        case .okx:
            return okxQuote(from: data, coin: coin)
        case .bybit:
            return bybitQuote(from: data, coin: coin)
        }
    }

    // MARK: - The shape of the day

    /// The closing prices of the last `hours` hours, oldest first: the shape
    /// of the day, for the line drawn beside a coin.
    ///
    /// Read when the panel opens rather than on every refresh — a line that
    /// redraws every ten seconds costs a request a minute for a shape nobody
    /// can take in that fast.
    public static func closes(
        coin: String,
        source: MarketSource = .binance,
        hours: Int = 24,
        session: URLSession = .shared
    ) async throws -> [Double] {
        var lastError: Error = PriceError.noData
        for host in source.hosts {
            guard let url = candlesURL(source: source, coin: coin, host: host, hours: hours) else { continue }
            do {
                let (data, response) = try await session.data(from: url)
                if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                    lastError = PriceError.badResponse(http.statusCode)
                    continue
                }
                let closes = try closes(from: data, source: source)
                if closes.isEmpty {
                    lastError = PriceError.noData
                    continue
                }
                return closes
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private static func candlesURL(source: MarketSource, coin: String, host: String, hours: Int) -> URL? {
        let pair = source.pair(for: coin)
        let limit = String(max(2, hours))
        var components: URLComponents?
        switch source {
        case .binance:
            components = URLComponents(string: host + "/api/v3/klines")
            components?.queryItems = [
                URLQueryItem(name: "symbol", value: pair),
                URLQueryItem(name: "interval", value: "1h"),
                URLQueryItem(name: "limit", value: limit),
            ]
        case .gate:
            components = URLComponents(string: host + "/api/v4/spot/candlesticks")
            components?.queryItems = [
                URLQueryItem(name: "currency_pair", value: pair),
                URLQueryItem(name: "interval", value: "1h"),
                URLQueryItem(name: "limit", value: limit),
            ]
        case .okx:
            components = URLComponents(string: host + "/api/v5/market/candles")
            components?.queryItems = [
                URLQueryItem(name: "instId", value: pair),
                URLQueryItem(name: "bar", value: "1H"),
                URLQueryItem(name: "limit", value: limit),
            ]
        case .bybit:
            components = URLComponents(string: host + "/v5/market/kline")
            components?.queryItems = [
                URLQueryItem(name: "category", value: "spot"),
                URLQueryItem(name: "symbol", value: pair),
                URLQueryItem(name: "interval", value: "60"),
                URLQueryItem(name: "limit", value: limit),
            ]
        }
        return components?.url
    }

    /// Where an exchange puts the closing price in a candle, and which end
    /// of the list it starts from.
    static func candleLayout(of source: MarketSource) -> (close: Int, newestFirst: Bool) {
        switch source {
        // Klines: open time, open, high, low, close, volume, …
        case .binance: (4, false)
        // Candlesticks: time, quote volume, close, high, low, open, …
        case .gate: (2, false)
        // Candles and klines: start, open, high, low, close, volume, …
        case .okx, .bybit: (4, true)
        }
    }

    /// The closing price of each candle in a candles response.
    ///
    /// A candle is a mixed array — a number of milliseconds, then strings of
    /// prices — so it is read positionally rather than decoded into a type.
    /// OKX and Bybit wrap their rows in an object; Binance and Gate send the
    /// rows alone.
    static func closes(from data: Data, source: MarketSource) throws -> [Double] {
        let layout = candleLayout(of: source)
        guard let rows = candleRows(from: data) else { throw PriceError.noData }

        let values: [Double] = rows.compactMap { row in
            guard row.count > layout.close else { return nil }
            if let value = row[layout.close] as? Double { return value }
            if let text = row[layout.close] as? String { return Double(text) }
            return nil
        }
        return layout.newestFirst ? values.reversed() : values
    }

    private static func candleRows(from data: Data) -> [[Any]]? {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        if let rows = object as? [[Any]] { return rows }
        guard let dictionary = object as? [String: Any] else { return nil }
        if let rows = dictionary["data"] as? [[Any]] { return rows }
        if let result = dictionary["result"] as? [String: Any],
           let rows = result["list"] as? [[Any]] { return rows }
        return nil
    }

    // MARK: - Does the exchange know this coin

    /// Reads one coin once, to check that the exchange knows it.
    public static func exists(
        coin: String,
        source: MarketSource = .binance,
        session: URLSession = .shared
    ) async -> Bool {
        let quotes = try? await quotes(for: [coin], source: source, session: session)
        return quotes?.isEmpty == false
    }
}

public enum PriceError: LocalizedError {
    case noData
    case badResponse(Int)
    /// The network, the proxy, or the exchange: whatever the message says.
    case unreachable(String)

    public var errorDescription: String? {
        switch self {
        case .noData: "没有拿到价格数据"
        case .badResponse(let code): "行情接口返回 HTTP \(code)"
        case .unreachable(let message): message
        }
    }
}

/// Reads the US dollar's rate in yuan, for showing prices in CNY.
public enum FXAPI {
    struct Latest: Decodable {
        let rates: [String: Double]
    }

    /// The rate from USD to CNY. The European Central Bank's reference rate
    /// updates once a day, which is enough for a price display.
    public static func usdToCNY(session: URLSession = .shared) async throws -> Double {
        guard var components = URLComponents(string: "https://api.frankfurter.app/latest") else {
            throw PriceError.noData
        }
        components.queryItems = [
            URLQueryItem(name: "from", value: "USD"),
            URLQueryItem(name: "to", value: "CNY"),
        ]
        guard let url = components.url else { throw PriceError.noData }
        let (data, _) = try await session.data(from: url)
        let latest = try JSONDecoder().decode(Latest.self, from: data)
        guard let rate = latest.rates["CNY"], rate > 0 else { throw PriceError.noData }
        return rate
    }
}
