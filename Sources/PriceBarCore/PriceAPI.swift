import Foundation

/// Reads prices and the shape of the day from an exchange.
///
/// Each exchange answers in its own shape: its own spelling of the pair, its
/// own field names, its own order of candles. One parser per exchange, each
/// tested against a captured response, is the only way to read four of them
/// without reading none of them correctly.
public enum PriceAPI {
    // MARK: - Quotes

    /// What a read of the panel's instruments came back with: the prices it
    /// found, in the order they were asked for, and for each one it did not
    /// find, why not.
    public struct Reading: Sendable, Equatable {
        public var quotes: [Quote]
        /// Keyed by instrument id. Never holds an id that is in `quotes`.
        public var missing: [String: Absence]

        public init(quotes: [Quote] = [], missing: [String: Absence] = [:]) {
            self.quotes = quotes
            self.missing = missing
        }

        /// The first reason the exchange could not be reached, if any was.
        public var unreachable: String? {
            for case let .unreachable(message) in missing.values { return message }
            return nil
        }
    }

    /// Why an instrument has no price.
    public enum Absence: Sendable, Equatable {
        /// The exchange answered, and does not list it on that market.
        case notListed
        /// The exchange, or that market of it, could not be reached; the
        /// reason in words, ready to show.
        case unreachable(String)
    }

    /// Reads every instrument from the exchange: spot and perpetuals each
    /// from their own market, side by side, put back in the order asked.
    ///
    /// Never throws: one market out of reach — Binance's contracts without a
    /// proxy — should not cost the other its prices, so each instrument
    /// reports for itself.
    public static func read(
        _ ids: [String],
        source: MarketSource = .binance,
        session: URLSession = .shared,
        strings: Strings = Strings(),
        pacing: RequestPacing = .shared
    ) async -> Reading {
        let wanted = ids.map(Instrument.init(id:))
        guard !wanted.isEmpty else { return Reading() }
        let spot = wanted.filter { $0.market == .spot }
        let perpetual = wanted.filter { $0.market == .perpetual }

        async let spotOutcomes = outcomes(
            for: spot, market: .spot, source: source, session: session, strings: strings, pacing: pacing
        )
        async let perpetualOutcomes = outcomes(
            for: perpetual, market: .perpetual, source: source, session: session, strings: strings, pacing: pacing
        )
        let all = await spotOutcomes + perpetualOutcomes

        var found: [String: Quote] = [:]
        var missing: [String: Absence] = [:]
        for outcome in all {
            switch outcome {
            case let .got(quote): found[quote.coin] = quote
            case let .absent(id, why): missing[id] = why
            }
        }
        return Reading(quotes: wanted.compactMap { found[$0.id] }, missing: missing)
    }

    /// Fetches every instrument's quote, in the order asked. Instruments the
    /// exchange does not list are left out; when nothing at all comes back,
    /// it throws why.
    public static func quotes(
        for ids: [String],
        source: MarketSource = .binance,
        session: URLSession = .shared,
        strings: Strings = Strings(),
        pacing: RequestPacing = .shared
    ) async throws -> [Quote] {
        let reading = await read(
            ids, source: source, session: session, strings: strings, pacing: pacing
        )
        if reading.quotes.isEmpty, !ids.isEmpty {
            throw reading.unreachable.map(PriceError.unreachable) ?? PriceError.noData
        }
        return reading.quotes
    }

    /// What one instrument's read came back with.
    ///
    /// A tuple would read the same, but the release optimiser drops the
    /// `for await` body when the element type is a tuple of optionals: the
    /// loop then runs zero times and every quote is lost. A named enum keeps
    /// the loop, and says what each case means.
    private enum Outcome: Sendable {
        case got(Quote)
        case absent(id: String, why: Absence)
    }

    /// The instruments of one market: in one request where the exchange
    /// answers for many at once, one request each otherwise.
    private static func outcomes(
        for instruments: [Instrument],
        market: Market,
        source: MarketSource,
        session: URLSession,
        strings: Strings,
        pacing: RequestPacing
    ) async -> [Outcome] {
        guard !instruments.isEmpty else { return [] }
        if source.answersManyAtOnce(on: market), instruments.count > 1 {
            switch await binanceBatch(instruments, session: session, pacing: pacing) {
            case let .success(quotes):
                let found = Set(quotes.map(\.coin))
                return quotes.map(Outcome.got) + instruments
                    .filter { !found.contains($0.id) }
                    .map { .absent(id: $0.id, why: .notListed) }
            case .failure(PriceError.badResponse(400)):
                // One code Binance does not list turns the whole request
                // away. Asked one by one, the others still get their price.
                break
            case let .failure(error):
                return instruments.map {
                    .absent(id: $0.id, why: .unreachable(describe(error, strings)))
                }
            }
        }
        return await oneByOne(
            instruments, source: source, session: session, strings: strings, pacing: pacing
        )
    }

    /// Reads one instrument per request, side by side.
    private static func oneByOne(
        _ instruments: [Instrument],
        source: MarketSource,
        session: URLSession,
        strings: Strings,
        pacing: RequestPacing
    ) async -> [Outcome] {
        await withTaskGroup(of: Outcome.self) { group in
            for instrument in instruments {
                group.addTask {
                    await outcome(
                        of: instrument, source: source, session: session,
                        strings: strings, pacing: pacing
                    )
                }
            }
            var all: [Outcome] = []
            for await outcome in group {
                all.append(outcome)
            }
            return all
        }
    }

    /// One instrument, trying the market's hosts in turn.
    ///
    /// The exchanges turn away a pair they do not list with HTTP 400, or
    /// answer 200 with nothing in it; anything else — a refused connection,
    /// a 403 or 451 from a blocked region — is the market being out of
    /// reach, which a proxy may fix and a different code will not.
    /// One cooldown per exchange, not per host name: every host of a source
    /// goes out over the same exit IP, and that IP is what gets limited.
    private static func pacingSlot(_ source: MarketSource) -> String {
        source.rawValue
    }

    private static func outcome(
        of instrument: Instrument,
        source: MarketSource,
        session: URLSession,
        strings: Strings,
        pacing: RequestPacing
    ) async -> Outcome {
        var problem = describe(PriceError.noData, strings)
        for host in source.hosts(for: instrument.market) {
            guard let url = tickerURL(source: source, instrument: instrument, host: host) else { continue }
            let key = pacingSlot(source)
            // A cooldown is this connection resting. Asking the next host
            // name over the same exit IP would send the same traffic again.
            if case let .wait(seconds, code) = await pacing.decision(for: key) {
                problem = describe(PriceError.rateLimited(code: code, seconds: seconds), strings)
                break
            }
            let sentAt = await pacing.stamp()
            do {
                let (data, response) = try await session.data(from: url)
                if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                    if http.statusCode == 400 {
                        return .absent(id: instrument.id, why: .notListed)
                    }
                    if http.statusCode == 429 || http.statusCode == 418 {
                        let seconds = await pacing.limited(
                            host: key, code: http.statusCode,
                            retryAfter: http.value(forHTTPHeaderField: "Retry-After")
                        )
                        problem = describe(
                            PriceError.rateLimited(code: http.statusCode, seconds: seconds), strings
                        )
                        // The limit is on our IP, not on the host name: this
                        // is exactly the "keep asking after a 429" that the
                        // exchange turns into a 418 ban.
                        break
                    }
                    problem = describe(PriceError.badResponse(http.statusCode), strings)
                    continue
                }
                // An answer, even one with no price in it, means this IP is
                // welcome again — as long as the request went out after the
                // cooldown, not before a sibling was refused.
                await pacing.succeeded(host: key, sentAt: sentAt)
                guard let quote = quote(from: data, source: source, instrument: instrument) else {
                    return .absent(id: instrument.id, why: .notListed)
                }
                return .got(quote)
            } catch {
                problem = describe(error, strings)
            }
        }
        return .absent(id: instrument.id, why: .unreachable(problem))
    }

    private static func tickerURL(source: MarketSource, instrument: Instrument, host: String) -> URL? {
        let symbol = source.symbol(for: instrument)
        let perpetual = instrument.market == .perpetual
        var components: URLComponents?
        switch source {
        case .binance:
            components = URLComponents(string: host + (perpetual ? "/fapi/v1/ticker/24hr" : "/api/v3/ticker/24hr"))
            components?.queryItems = [URLQueryItem(name: "symbol", value: symbol)]
        case .gate:
            components = URLComponents(string: host + (perpetual ? "/api/v4/futures/usdt/tickers" : "/api/v4/spot/tickers"))
            components?.queryItems = [URLQueryItem(name: perpetual ? "contract" : "currency_pair", value: symbol)]
        case .okx:
            components = URLComponents(string: host + "/api/v5/market/ticker")
            components?.queryItems = [URLQueryItem(name: "instId", value: symbol)]
        case .bybit:
            components = URLComponents(string: host + "/v5/market/tickers")
            components?.queryItems = [
                URLQueryItem(name: "category", value: perpetual ? "linear" : "spot"),
                URLQueryItem(name: "symbol", value: symbol),
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
    /// request for the whole panel's spot coins. A single symbol comes back
    /// as an object, a list of them as an array.
    private static func binanceBatch(
        _ instruments: [Instrument], session: URLSession, pacing: RequestPacing
    ) async -> Result<[Quote], Error> {
        var lastError: Error = PriceError.noData

        for host in MarketSource.binance.hosts(for: .spot) {
            guard var components = URLComponents(string: host + "/api/v3/ticker/24hr") else { continue }
            // The list has to be percent-encoded by hand: the query is read
            // as already-encoded by URLComponents, and a pair of brackets
            // left as they are is a request for nothing.
            let list = try? JSONSerialization.data(
                withJSONObject: instruments.map { MarketSource.binance.symbol(for: $0) })
            let encoded = list
                .flatMap { String(data: $0, encoding: .utf8) }?
                .addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "[]"
            components.percentEncodedQuery = "symbols=" + encoded
            guard let url = components.url else { continue }
            let key = pacingSlot(.binance)
            if case let .wait(seconds, code) = await pacing.decision(for: key) {
                lastError = PriceError.rateLimited(code: code, seconds: seconds)
                break
            }
            let sentAt = await pacing.stamp()

            do {
                let (data, response) = try await session.data(from: url)
                if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                    if http.statusCode == 429 || http.statusCode == 418 {
                        let seconds = await pacing.limited(
                            host: key, code: http.statusCode,
                            retryAfter: http.value(forHTTPHeaderField: "Retry-After")
                        )
                        lastError = PriceError.rateLimited(code: http.statusCode, seconds: seconds)
                        break
                    }
                    lastError = PriceError.badResponse(http.statusCode)
                    // A pair it does not list is the same answer from every
                    // host: no use asking the next.
                    if http.statusCode == 400 { break }
                    continue
                }
                await pacing.succeeded(host: key, sentAt: sentAt)
                return .success(try binanceQuotes(from: data, instruments: instruments))
            } catch {
                lastError = error
            }
        }
        return .failure(lastError)
    }

    /// Spot coins by code, for the tests that predate contracts.
    static func binanceQuotes(from data: Data, coins: [String]) throws -> [Quote] {
        try binanceQuotes(from: data, instruments: coins.map { Instrument(code: $0, market: .spot) })
    }

    /// The quotes in a Binance ticker answer, spot or perpetual: the two
    /// markets name a pair the same way and answer in the same shape.
    static func binanceQuotes(from data: Data, instruments: [Instrument]) throws -> [Quote] {
        let decoder = JSONDecoder()
        let tickers: [BinanceTicker]
        if let list = try? decoder.decode([BinanceTicker].self, from: data) {
            tickers = list
        } else if let one = try? decoder.decode(BinanceTicker.self, from: data) {
            tickers = [one]
        } else {
            throw PriceError.noData
        }

        var bySymbol: [String: BinanceTicker] = [:]
        for ticker in tickers {
            bySymbol[ticker.symbol.uppercased()] = ticker
        }
        return instruments.compactMap { instrument in
            guard let ticker = bySymbol[MarketSource.binance.symbol(for: instrument)],
                  let price = Double(ticker.lastPrice)
            else { return nil }
            return Quote(
                coin: instrument.id,
                price: price,
                change: Double(ticker.priceChangePercent) ?? 0
            )
        }
    }

    /// Gate names the pair with an underscore and spells the change as a
    /// percentage already. Its spot market calls the pair `currency_pair`,
    /// its contracts call it `contract`; the rest is the same.
    struct GateTicker: Decodable {
        let pair: String
        let last: String?
        let change: String?

        enum CodingKeys: String, CodingKey {
            case pair = "currency_pair"
            case contract
            case last
            case change = "change_percentage"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            pair = try container.decodeIfPresent(String.self, forKey: .pair)
                ?? container.decode(String.self, forKey: .contract)
            last = try container.decodeIfPresent(String.self, forKey: .last)
            change = try container.decodeIfPresent(String.self, forKey: .change)
        }
    }

    static func gateQuote(from data: Data, instrument: Instrument) -> Quote? {
        let symbol = MarketSource.gate.symbol(for: instrument)
        guard let rows = try? JSONDecoder().decode([GateTicker].self, from: data),
              let row = rows.first(where: { $0.pair.uppercased() == symbol }),
              let last = row.last, let price = Double(last)
        else { return nil }
        return Quote(coin: instrument.id, price: price, change: Double(row.change ?? "") ?? 0)
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

    static func okxQuote(from data: Data, instrument: Instrument) -> Quote? {
        guard let response = try? JSONDecoder().decode(OKXResponse.self, from: data),
              let ticker = response.data.first,
              let price = Double(ticker.last)
        else { return nil }
        let open = Double(ticker.open24h) ?? 0
        let change = open > 0 ? (price / open - 1) * 100 : 0
        return Quote(coin: instrument.id, price: price, change: change)
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

    static func bybitQuote(from data: Data, instrument: Instrument) -> Quote? {
        guard let response = try? JSONDecoder().decode(BybitResponse.self, from: data),
              let ticker = response.result.list.first,
              let price = Double(ticker.lastPrice)
        else { return nil }
        return Quote(
            coin: instrument.id,
            price: price,
            change: (Double(ticker.price24hPcnt) ?? 0) * 100
        )
    }

    /// One instrument's quote, read the way its exchange writes it.
    static func quote(from data: Data, source: MarketSource, instrument: Instrument) -> Quote? {
        switch source {
        case .binance:
            return (try? binanceQuotes(from: data, instruments: [instrument]))?.first
        case .gate:
            return gateQuote(from: data, instrument: instrument)
        case .okx:
            return okxQuote(from: data, instrument: instrument)
        case .bybit:
            return bybitQuote(from: data, instrument: instrument)
        }
    }

    /// One instrument's quote, named by its id: "BTC", or "XAU.P".
    static func quote(from data: Data, source: MarketSource, coin: String) -> Quote? {
        quote(from: data, source: source, instrument: Instrument(id: coin))
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
        session: URLSession = .shared,
        pacing: RequestPacing = .shared
    ) async throws -> [Double] {
        let instrument = Instrument(id: coin)
        var lastError: Error = PriceError.noData
        for host in source.hosts(for: instrument.market) {
            guard let url = candlesURL(source: source, instrument: instrument, host: host, hours: hours) else { continue }
            let key = pacingSlot(source)
            if case let .wait(seconds, code) = await pacing.decision(for: key) {
                lastError = PriceError.rateLimited(code: code, seconds: seconds)
                break
            }
            let sentAt = await pacing.stamp()
            do {
                let (data, response) = try await session.data(from: url)
                if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                    if http.statusCode == 429 || http.statusCode == 418 {
                        let seconds = await pacing.limited(
                            host: key, code: http.statusCode,
                            retryAfter: http.value(forHTTPHeaderField: "Retry-After")
                        )
                        lastError = PriceError.rateLimited(code: http.statusCode, seconds: seconds)
                        break
                    }
                    lastError = PriceError.badResponse(http.statusCode)
                    continue
                }
                await pacing.succeeded(host: key, sentAt: sentAt)
                let closes = try closes(from: data, source: source, market: instrument.market)
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

    private static func candlesURL(source: MarketSource, instrument: Instrument, host: String, hours: Int) -> URL? {
        let symbol = source.symbol(for: instrument)
        let perpetual = instrument.market == .perpetual
        let limit = String(max(2, hours))
        var components: URLComponents?
        switch source {
        case .binance:
            components = URLComponents(string: host + (perpetual ? "/fapi/v1/klines" : "/api/v3/klines"))
            components?.queryItems = [
                URLQueryItem(name: "symbol", value: symbol),
                URLQueryItem(name: "interval", value: "1h"),
                URLQueryItem(name: "limit", value: limit),
            ]
        case .gate:
            components = URLComponents(string: host + (perpetual ? "/api/v4/futures/usdt/candlesticks" : "/api/v4/spot/candlesticks"))
            components?.queryItems = [
                URLQueryItem(name: perpetual ? "contract" : "currency_pair", value: symbol),
                URLQueryItem(name: "interval", value: "1h"),
                URLQueryItem(name: "limit", value: limit),
            ]
        case .okx:
            components = URLComponents(string: host + "/api/v5/market/candles")
            components?.queryItems = [
                URLQueryItem(name: "instId", value: symbol),
                URLQueryItem(name: "bar", value: "1H"),
                URLQueryItem(name: "limit", value: limit),
            ]
        case .bybit:
            components = URLComponents(string: host + "/v5/market/kline")
            components?.queryItems = [
                URLQueryItem(name: "category", value: perpetual ? "linear" : "spot"),
                URLQueryItem(name: "symbol", value: symbol),
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
    static func closes(from data: Data, source: MarketSource, market: Market = .spot) throws -> [Double] {
        // Gate's contracts send each candle as an object, the close under
        // "c", oldest first; its spot market sends arrays like the others.
        if source == .gate, market == .perpetual {
            guard let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                throw PriceError.noData
            }
            return rows.compactMap { row in
                if let text = row["c"] as? String { return Double(text) }
                return row["c"] as? Double
            }
        }

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

    // MARK: - Does the exchange list this code

    /// Asks both markets for a code at once, to see which of them list it:
    /// what the add-a-coin popover offers to add.
    public static func lookUp(
        code: String,
        source: MarketSource = .binance,
        session: URLSession = .shared,
        strings: Strings = Strings(),
        pacing: RequestPacing = .shared
    ) async -> Reading {
        let ids = Market.allCases.map { Instrument(code: code, market: $0).id }
        return await read(
            ids, source: source, session: session, strings: strings, pacing: pacing
        )
    }
}

public enum PriceError: LocalizedError, Sendable {
    case noData
    case badResponse(Int)
    /// The exchange asked us to stop for `seconds`, after a 429 or a 418.
    case rateLimited(code: Int, seconds: Int)
    /// The network, the proxy, or the exchange: whatever the message says.
    case unreachable(String)

    public var errorDescription: String? {
        let strings = Strings()
        switch self {
        case .noData: return strings.noData
        case let .badResponse(code): return strings.badResponse(code)
        case let .rateLimited(code, seconds): return strings.rateLimited(code, seconds)
        case let .unreachable(message): return message
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
