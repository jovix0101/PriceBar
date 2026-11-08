import Foundation
import Testing
@testable import PriceBarCore

struct StreamAddressTests {
    private func instruments(_ ids: String...) -> [Instrument] { ids.map(Instrument.init(id:)) }

    private func urls(_ source: MarketSource, _ ids: String...) -> [String] {
        source.streamWires(for: ids.map(Instrument.init(id:))).map(\.url.absoluteString)
    }

    @Test("Binance spot is pushed from its market data host")
    func spotAddress() {
        #expect(urls(.binance, "BTC", "ETH")
            == ["wss://data-stream.binance.vision/stream?streams=btcusdt@ticker/ethusdt@ticker"])
    }

    @Test("Binance contracts use the routed /market path: the old /ws path connects and stays silent")
    func perpetualAddress() {
        #expect(urls(.binance, "BTC.P", "QQQ.P")
            == ["wss://fstream.binance.com/market/stream?streams=btcusdt@ticker/qqqusdt@ticker"])
    }

    @Test("Gate and Bybit keep a connection per market")
    func perMarket() {
        #expect(urls(.gate, "BTC", "QQQ.P")
            == ["wss://api.gateio.ws/ws/v4/", "wss://fx-ws.gateio.ws/v4/ws/usdt"])
        #expect(urls(.bybit, "BTC", "QQQ.P")
            == ["wss://stream.bybit.com/v5/public/spot", "wss://stream.bybit.com/v5/public/linear"])
    }

    @Test("OKX carries both markets on one connection, on port 443")
    func okxOneConnection() {
        #expect(urls(.okx, "BTC", "QQQ.P") == ["wss://ws.okx.com/ws/v5/public"])
    }

    @Test("Every source pushes", arguments: MarketSource.allCases)
    func everySourcePushes(source: MarketSource) {
        #expect(source.pushesPrices)
        #expect(source.streamWires(for: []).isEmpty)
    }
}

struct StreamSubscriptionTests {
    private let now = Date(timeIntervalSince1970: 1_794_074_562)

    private func wires(_ source: MarketSource, _ ids: String...) -> [StreamWire] {
        source.streamWires(for: ids.map(Instrument.init(id:)))
    }

    @Test("Binance names its streams in the address and sends nothing")
    func binanceSendsNothing() {
        #expect(wires(.binance, "BTC").allSatisfy { $0.subscriptions(at: now).isEmpty })
        #expect(wires(.binance, "BTC").allSatisfy { $0.heartbeat(at: now) == nil })
    }

    @Test("Gate asks for every pair on its own: one unknown pair fails a whole spot subscription")
    func gateOnePerPair() {
        let spot = wires(.gate, "BTC", "ETH")[0]
        #expect(spot.subscriptions(at: now) == [
            #"{"time":1794074562,"channel":"spot.tickers","event":"subscribe","payload":["BTC_USDT"]}"#,
            #"{"time":1794074562,"channel":"spot.tickers","event":"subscribe","payload":["ETH_USDT"]}"#,
        ])
        #expect(spot.heartbeat(at: now) == #"{"time":1794074562,"channel":"spot.ping"}"#)
        let contracts = wires(.gate, "QQQ.P")[0]
        #expect(contracts.subscriptions(at: now)
            == [#"{"time":1794074562,"channel":"futures.tickers","event":"subscribe","payload":["QQQ_USDT"]}"#])
        #expect(contracts.heartbeat(at: now) == #"{"time":1794074562,"channel":"futures.ping"}"#)
    }

    @Test("OKX asks for everything at once: it fails only the unknown instrument")
    func okxAllAtOnce() {
        let wire = wires(.okx, "BTC", "QQQ.P")[0]
        #expect(wire.subscriptions(at: now) == [
            #"{"op":"subscribe","args":[{"channel":"tickers","instId":"BTC-USDT"},{"channel":"tickers","instId":"QQQ-USDT-SWAP"}]}"#,
        ])
        #expect(wire.heartbeat(at: now) == "ping")
    }

    @Test("Bybit asks for every symbol on its own: one unknown symbol fails the whole request")
    func bybitOnePerSymbol() {
        let spot = wires(.bybit, "BTC", "ETH")[0]
        #expect(spot.subscriptions(at: now) == [
            #"{"op":"subscribe","args":["tickers.BTCUSDT"]}"#,
            #"{"op":"subscribe","args":["tickers.ETHUSDT"]}"#,
        ])
        #expect(spot.heartbeat(at: now) == #"{"op":"ping"}"#)
    }
}

/// The messages here are cut down from what the exchanges sent on
/// 2026-11-08, keeping the fields that are read and a few that are not.
struct StreamReaderTests {
    private func reader(_ source: MarketSource, _ ids: String...) -> StreamReader {
        StreamReader(wire: source.streamWires(for: ids.map(Instrument.init(id:)))[0])
    }

    private func binance(symbol: String = "BTCUSDT", last: String = "75953.78", change: String = "-0.076") -> String {
        #"{"stream":"\#(symbol.lowercased())@ticker","data":{"e":"24hrTicker","s":"\#(symbol)","p":"-57.59","P":"\#(change)","c":"\#(last)"}}"#
    }

    @Test("A Binance ticker becomes the quote of the instrument that was asked for")
    func readsBinance() {
        var reader = reader(.binance, "BTC.P")
        #expect(reader.quotes(in: binance()) == [Quote(coin: "BTC.P", price: 75953.78, change: -0.076)])
    }

    @Test("Frames that are not a usable price are dropped")
    func dropsTheRest() {
        var reader = reader(.binance, "BTC.P")
        #expect(reader.quotes(in: binance(symbol: "ETHUSDT")).isEmpty)
        #expect(reader.quotes(in: binance(last: "0")).isEmpty)
        #expect(reader.quotes(in: binance(last: "nan")).isEmpty)
        #expect(reader.quotes(in: "not json").isEmpty)
        #expect(reader.quotes(in: #"{"stream":"!serverShutdown","data":{"e":"serverShutdown","E":1}}"#).isEmpty)
    }

    @Test("Gate spot sends one ticker, its contracts a list; the change is already in percent")
    func readsGate() {
        var spot = reader(.gate, "BTC")
        #expect(spot.quotes(in: #"{"time":1794074562,"channel":"spot.tickers","event":"update","result":{"currency_pair":"BTC_USDT","last":"75847.4","change_percentage":"0.4099","base_volume":"5212.3"}}"#)
            == [Quote(coin: "BTC", price: 75847.4, change: 0.4099)])
        #expect(spot.quotes(in: #"{"time":1794074562,"channel":"spot.tickers","event":"subscribe","result":{"status":"success"}}"#).isEmpty)
        #expect(spot.quotes(in: #"{"time":1794074588,"channel":"spot.pong","event":"","result":null}"#).isEmpty)

        var contracts = reader(.gate, "QQQ.P")
        #expect(contracts.quotes(in: #"{"time":1794074569,"channel":"futures.tickers","event":"update","result":[{"contract":"QQQ_USDT","last":"658.04","change_percentage":"0.3094","total_size":"607805128"}]}"#)
            == [Quote(coin: "QQQ.P", price: 658.04, change: 0.3094)])
    }

    @Test("OKX gives the open of the last 24 hours; the change is worked out from it")
    func readsOKX() throws {
        var reader = reader(.okx, "BTC", "QQQ.P")
        let quotes = reader.quotes(in: #"{"arg":{"channel":"tickers","instId":"QQQ-USDT-SWAP"},"data":[{"instType":"SWAP","instId":"QQQ-USDT-SWAP","last":"660","open24h":"600","high24h":"661"}]}"#)
        let quote = try #require(quotes.first)
        #expect(quote.coin == "QQQ.P")
        #expect(quote.price == 660)
        #expect(abs(quote.change - 10) < 1e-9)
        #expect(reader.quotes(in: "pong").isEmpty)
        #expect(reader.quotes(in: #"{"event":"error","msg":"instId:ZZZQ-USDT doesn't exist.","code":"60018"}"#).isEmpty)
        #expect(reader.quotes(in: #"{"event":"subscribe","arg":{"channel":"tickers","instId":"BTC-USDT"}}"#).isEmpty)
    }

    @Test("Bybit spells the change as a fraction")
    func readsBybitSpot() {
        var reader = reader(.bybit, "BTC")
        #expect(reader.quotes(in: #"{"topic":"tickers.BTCUSDT","type":"snapshot","data":{"symbol":"BTCUSDT","lastPrice":"75850.2","price24hPcnt":"0.0038"}}"#)
            == [Quote(coin: "BTC", price: 75850.2, change: 0.38)])
        #expect(reader.quotes(in: #"{"success":true,"ret_msg":"pong","op":"ping"}"#).isEmpty)
    }

    @Test("Bybit contracts send the full ticker once, then only what changed")
    func readsBybitDeltas() {
        var reader = reader(.bybit, "QQQ.P")
        func check(_ text: String, price: Double, change: Double) {
            let quotes = reader.quotes(in: text)
            #expect(quotes.count == 1)
            #expect(quotes.first?.coin == "QQQ.P")
            #expect(quotes.first?.price == price)
            #expect(abs((quotes.first?.change ?? .nan) - change) < 1e-9)
        }
        check(#"{"topic":"tickers.QQQUSDT","type":"snapshot","data":{"symbol":"QQQUSDT","lastPrice":"657.15","price24hPcnt":"-0.0034","bid1Price":"657.1"}}"#,
              price: 657.15, change: -0.34)
        check(#"{"topic":"tickers.QQQUSDT","type":"delta","data":{"symbol":"QQQUSDT","bid1Price":"657.2"}}"#,
              price: 657.15, change: -0.34)
        check(#"{"topic":"tickers.QQQUSDT","type":"delta","data":{"symbol":"QQQUSDT","lastPrice":"658"}}"#,
              price: 658, change: -0.34)
    }

    @Test("A Bybit delta before any snapshot has no price to give")
    func bybitDeltaFirst() {
        var reader = reader(.bybit, "QQQ.P")
        #expect(reader.quotes(in: #"{"topic":"tickers.QQQUSDT","type":"delta","data":{"symbol":"QQQUSDT","bid1Price":"657.2"}}"#).isEmpty)
    }
}

struct StreamBackoffTests {
    @Test("Reconnects double from a second to a minute", arguments: [
        (1, 1.0), (2, 2.0), (3, 4.0), (4, 8.0), (5, 16.0), (6, 32.0), (7, 60.0), (40, 60.0),
    ])
    func doubles(failures: Int, seconds: Double) {
        #expect(PriceStream.backoff(failures: failures) == seconds)
    }
}

struct ReadPlanTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)
    private func ago(_ seconds: Double) -> Date { now.addingTimeInterval(-seconds) }

    @Test("Without a live stream everything is read, however fresh")
    func polledCoinsAreAlwaysRead() {
        let asked = ReadPlan.coins(
            ["BTC", "ETH"], live: [], seen: ["BTC": ago(1)], notListed: ["ETH": ago(1)], now: now)
        #expect(asked == ["BTC", "ETH"])
    }

    @Test("A live coin with a recent price costs no request")
    func liveCoinIsLeftAlone() {
        let asked = ReadPlan.coins(["BTC"], live: ["BTC"], seen: ["BTC": ago(59)], notListed: [:], now: now)
        #expect(asked.isEmpty)
    }

    @Test("A live coin with no price yet, or quiet for a minute, is asked once")
    func quietCoinIsChecked() {
        #expect(ReadPlan.coins(["QQQ.P"], live: ["QQQ.P"], seen: [:], notListed: [:], now: now) == ["QQQ.P"])
        #expect(ReadPlan.coins(
            ["QQQ.P"], live: ["QQQ.P"], seen: ["QQQ.P": ago(60)], notListed: [:], now: now) == ["QQQ.P"])
    }

    @Test("A code the exchange does not list is asked about every five minutes while live")
    func unlistedCoinWaits() {
        #expect(ReadPlan.coins(
            ["NOPE"], live: ["NOPE"], seen: [:], notListed: ["NOPE": ago(299)], now: now).isEmpty)
        #expect(ReadPlan.coins(
            ["NOPE"], live: ["NOPE"], seen: [:], notListed: ["NOPE": ago(300)], now: now) == ["NOPE"])
    }

    private func reading(_ quotes: [Quote] = [], _ missing: [String: PriceAPI.Absence] = [:]) -> PriceAPI.Reading {
        PriceAPI.Reading(quotes: quotes, missing: missing)
    }

    private let old = Quote(coin: "BTC", price: 1, change: 0)
    private let other = Quote(coin: "ETH", price: 2, change: 0)
    private let fresh = Quote(coin: "BTC", price: 9, change: 1)

    @Test("A read of some coins leaves the others' prices alone, in panel order")
    func partialRead() {
        let merged = ReadPlan.merged(
            coins: ["ETH", "BTC"], asked: ["BTC"], reading: reading([fresh]),
            quotes: [old, other], missing: [:], live: ["ETH"])
        #expect(merged.quotes == [other, fresh])
        #expect(merged.missing.isEmpty)
    }

    @Test("A failed check does not take a live coin's price away")
    func failedCheckKeepsLivePrice() {
        let merged = ReadPlan.merged(
            coins: ["BTC"], asked: ["BTC"], reading: reading([], ["BTC": .unreachable("HTTP 418")]),
            quotes: [old], missing: [:], live: ["BTC"])
        #expect(merged.quotes == [old])
        #expect(merged.missing.isEmpty)
    }

    @Test("A live coin with no price yet says why it has none")
    func failedCheckWithoutPrice() {
        let merged = ReadPlan.merged(
            coins: ["QQQ.P"], asked: ["QQQ.P"], reading: reading([], ["QQQ.P": .unreachable("HTTP 418")]),
            quotes: [], missing: [:], live: ["QQQ.P"])
        #expect(merged.quotes.isEmpty)
        #expect(merged.missing == ["QQQ.P": .unreachable("HTTP 418")])
    }

    @Test("A polled coin that failed becomes a missing row, as it always has")
    func polledFailureIsMissing() {
        let merged = ReadPlan.merged(
            coins: ["BTC", "ETH"], asked: ["BTC"], reading: reading([], ["BTC": .unreachable("x")]),
            quotes: [old, other], missing: [:], live: ["ETH"])
        #expect(merged.quotes == [other])
        #expect(merged.missing == ["BTC": .unreachable("x")])
    }

    @Test("A row left out of this read stays as it was; a coin off the panel goes")
    func untouchedRowsStay() {
        let merged = ReadPlan.merged(
            coins: ["BTC", "NOPE"], asked: ["BTC"], reading: reading([fresh]),
            quotes: [old, other], missing: ["NOPE": .notListed, "GONE": .notListed], live: [])
        #expect(merged.quotes == [fresh])
        #expect(merged.missing == ["NOPE": .notListed])
    }

    @Test("A pushed price replaces the coin's price and clears its missing row")
    func pushedPrice() {
        let merged = ReadPlan.pushed(
            [fresh, Quote(coin: "GONE", price: 3, change: 0)],
            coins: ["ETH", "BTC"], quotes: [other], missing: ["BTC": .unreachable("x")])
        #expect(merged.quotes == [other, fresh])
        #expect(merged.missing.isEmpty)
    }
}

// MARK: - The connection

private final class FakeSocket: PriceSocket, @unchecked Sendable {
    private let lock = NSLock()
    private var frames: [String]
    private var waiting: CheckedContinuation<String, Error>?
    private var closedFlag = false
    private var sentTexts: [String] = []
    private let answersPings: Bool
    let refusal: (code: Int, retryAfter: String?)?

    init(frames: [String] = [], answersPings: Bool = true, refusal: (Int, String?)? = nil) {
        self.frames = frames
        self.answersPings = answersPings
        self.refusal = refusal.map { (code: $0.0, retryAfter: $0.1) }
    }

    var closed: Bool { lock.withLock { closedFlag } }

    func open() {}

    func receive() async throws -> String {
        if refusal != nil { throw URLError(.badServerResponse) }
        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            defer { lock.unlock() }
            if closedFlag {
                continuation.resume(throwing: URLError(.cancelled))
            } else if !frames.isEmpty {
                continuation.resume(returning: frames.removeFirst())
            } else {
                waiting = continuation
            }
        }
    }

    func send(_ text: String) async throws {
        lock.withLock { sentTexts.append(text) }
    }

    var sent: [String] { lock.withLock { sentTexts } }

    func ping(_ done: @escaping @Sendable (Bool) -> Void) {
        if answersPings && refusal == nil { done(true) }
    }

    func close() {
        let pending: CheckedContinuation<String, Error>? = lock.withLock {
            closedFlag = true
            defer { waiting = nil }
            return waiting
        }
        pending?.resume(throwing: URLError(.cancelled))
    }
}

/// Hands out the sockets a test prepared, then ones that sit quietly open.
private final class Sockets: @unchecked Sendable {
    private let lock = NSLock()
    private var queue: [FakeSocket]
    private(set) var urls: [URL] = []
    private(set) var made: [FakeSocket] = []

    init(_ queue: [FakeSocket] = []) { self.queue = queue }

    func connect(_ url: URL) -> any PriceSocket {
        lock.withLock {
            urls.append(url)
            let socket = queue.isEmpty ? FakeSocket() : queue.removeFirst()
            made.append(socket)
            return socket
        }
    }

    var count: Int { lock.withLock { urls.count } }
    var all: [FakeSocket] { lock.withLock { made } }
}

private let quick = PriceStream.Timing(ping: 0.01, silence: 0.05, flush: 0.01, steady: 60, retryScale: 0.001)

private func ticker(_ symbol: String, _ price: String) -> String {
    #"{"stream":"x","data":{"s":"\#(symbol)","c":"\#(price)","P":"1.5"}}"#
}

/// Reads events until one satisfies the test or a second has gone by.
private func nextEvent(
    of stream: PriceStream, where wanted: @escaping @Sendable (PriceStream.Event) -> Bool
) async -> PriceStream.Event? {
    await withTaskGroup(of: PriceStream.Event?.self) { group in
        group.addTask {
            for await event in stream.events where wanted(event) { return event }
            return nil
        }
        group.addTask {
            try? await Task.sleep(for: .seconds(1))
            return nil
        }
        let first = await group.next() ?? nil
        group.cancelAll()
        return first
    }
}

@Suite(.serialized)
struct PriceStreamTests {
    private func make(
        _ ids: [String], _ sockets: Sockets, source: MarketSource = .binance,
        pacing: RequestPacing = RequestPacing()
    ) -> PriceStream {
        PriceStream(
            source: source, instruments: ids.map(Instrument.init(id:)),
            pacing: pacing, timing: quick, connect: { sockets.connect($0) }
        )
    }

    @Test("One connection per market, and only the markets on the panel")
    func oneConnectionPerMarket() async {
        let sockets = Sockets()
        let stream = make(["BTC", "ETH", "BTC.P"], sockets)
        await stream.start()
        _ = await nextEvent(of: stream) { if case .live = $0 { true } else { false } }
        try? await Task.sleep(for: .milliseconds(30))
        await stream.stop()
        #expect(sockets.count == 2)
        #expect(Set(sockets.urls.compactMap(\.host))
            == ["data-stream.binance.vision", "fstream.binance.com"])
    }

    @Test("An open connection says so, even before a quiet market has traded")
    func saysLive() async {
        let sockets = Sockets()
        let stream = make(["QQQ.P"], sockets)
        await stream.start()
        let event = await nextEvent(of: stream) { if case .live = $0 { true } else { false } }
        await stream.stop()
        #expect(event == .live(["QQQ.P"], true))
    }

    @Test("Prices are handed over together, the newest of each coin")
    func coalesces() async {
        let sockets = Sockets([FakeSocket(frames: [ticker("BTCUSDT", "1"), ticker("BTCUSDT", "2"), ticker("ETHUSDT", "3")])])
        let stream = make(["BTC", "ETH"], sockets)
        await stream.start()
        let event = await nextEvent(of: stream) {
            if case let .quotes(quotes) = $0 { quotes.count == 2 } else { false }
        }
        await stream.stop()
        guard case let .quotes(quotes)? = event else {
            Issue.record("no prices arrived")
            return
        }
        #expect(quotes.first { $0.coin == "BTC" }?.price == 2)
        #expect(quotes.first { $0.coin == "ETH" }?.price == 3)
    }

    @Test("A connection that drops says so and opens again")
    func reconnects() async {
        let first = FakeSocket()
        let sockets = Sockets([first])
        let stream = make(["BTC"], sockets)
        await stream.start()
        _ = await nextEvent(of: stream) { $0 == .live(["BTC"], true) }
        first.close()
        let down = await nextEvent(of: stream) { $0 == .live(["BTC"], false) }
        let up = await nextEvent(of: stream) { $0 == .live(["BTC"], true) }
        await stream.stop()
        #expect(down != nil)
        #expect(up != nil)
        #expect(sockets.count >= 2)
    }

    @Test("A connection that stops answering pings is treated as dead")
    func silentSocketIsClosed() async {
        let mute = FakeSocket(frames: [ticker("BTCUSDT", "1")], answersPings: false)
        let sockets = Sockets([mute])
        let stream = make(["BTC"], sockets)
        await stream.start()
        _ = await nextEvent(of: stream) { $0 == .live(["BTC"], false) }
        _ = await nextEvent(of: stream) { $0 == .live(["BTC"], true) }
        await stream.stop()
        #expect(mute.closed)
        #expect(sockets.count >= 2)
    }

    @Test("A handshake refused with 418 waits out the ban, and the polling waits too")
    func refusedHandshake() async {
        let pacing = RequestPacing()
        let sockets = Sockets([FakeSocket(refusal: (418, "600"))])
        let stream = make(["BTC.P"], sockets, pacing: pacing)
        await stream.start()
        try? await Task.sleep(for: .milliseconds(120))
        await stream.stop()
        #expect(sockets.count == 1)
        #expect(await pacing.decision(for: PriceStream.pacingSlot(.binance)) == .wait(seconds: 600, code: 418))
        #expect(await pacing.decision(for: "binance") == .wait(seconds: 600, code: 418))
    }

    @Test("A ban on the polling does not stop the stream: Binance points there during one")
    func pollingBanLeavesStream() async {
        let pacing = RequestPacing()
        await pacing.limited(host: "binance", code: 418, retryAfter: "600")
        let sockets = Sockets()
        let stream = make(["BTC.P"], sockets, pacing: pacing)
        await stream.start()
        let event = await nextEvent(of: stream) { $0 == .live(["BTC.P"], true) }
        await stream.stop()
        #expect(event != nil)
        #expect(await pacing.decision(for: "binance") == .wait(seconds: 600, code: 418))
    }

    @Test("Subscriptions go out on opening, and the exchange's heartbeat once live")
    func subscribesAndBeats() async {
        let socket = FakeSocket()
        let sockets = Sockets([socket])
        let stream = make(["BTC", "ETH"], sockets, source: .bybit)
        await stream.start()
        _ = await nextEvent(of: stream) { $0 == .live(["BTC", "ETH"], true) }
        // The heartbeat goes out on a watchdog tick after the connection is
        // live; a slow machine may need several ticks.
        for _ in 0..<100 where !socket.sent.dropFirst(2).contains(#"{"op":"ping"}"#) {
            try? await Task.sleep(for: .milliseconds(10))
        }
        await stream.stop()
        #expect(Array(socket.sent.prefix(2)) == [
            #"{"op":"subscribe","args":["tickers.BTCUSDT"]}"#,
            #"{"op":"subscribe","args":["tickers.ETHUSDT"]}"#,
        ])
        #expect(socket.sent.dropFirst(2).contains(#"{"op":"ping"}"#))
    }

    @Test("A refused handshake cools the stream of that exchange only")
    func refusalPerExchange() async {
        let pacing = RequestPacing()
        let sockets = Sockets([FakeSocket(refusal: (429, "120"))])
        let stream = make(["BTC"], sockets, source: .gate, pacing: pacing)
        await stream.start()
        try? await Task.sleep(for: .milliseconds(120))
        await stream.stop()
        #expect(await pacing.decision(for: PriceStream.pacingSlot(.gate)) != .proceed)
        #expect(await pacing.decision(for: "gate") != .proceed)
        #expect(await pacing.decision(for: PriceStream.pacingSlot(.binance)) == .proceed)
    }

    @Test("OKX prices arrive from one connection for both markets")
    func okxBothMarkets() async {
        let frames = [
            #"{"arg":{"channel":"tickers","instId":"BTC-USDT"},"data":[{"instId":"BTC-USDT","last":"75000","open24h":"75000"}]}"#,
            #"{"arg":{"channel":"tickers","instId":"QQQ-USDT-SWAP"},"data":[{"instId":"QQQ-USDT-SWAP","last":"660","open24h":"660"}]}"#,
        ]
        let sockets = Sockets([FakeSocket(frames: frames)])
        let stream = make(["BTC", "QQQ.P"], sockets, source: .okx)
        await stream.start()
        let event = await nextEvent(of: stream) {
            if case let .quotes(quotes) = $0 { quotes.count == 2 } else { false }
        }
        await stream.stop()
        #expect(sockets.count == 1)
        guard case let .quotes(quotes)? = event else {
            Issue.record("no prices arrived")
            return
        }
        #expect(Set(quotes.map(\.coin)) == ["BTC", "QQQ.P"])
    }

    @Test("Stopping closes the sockets and ends the events")
    func stopCloses() async {
        let sockets = Sockets()
        let stream = make(["BTC"], sockets)
        await stream.start()
        _ = await nextEvent(of: stream) { $0 == .live(["BTC"], true) }
        await stream.stop()
        #expect(sockets.all.allSatisfy { $0.closed })
        for await _ in stream.events {}
    }

    @Test("Reconnecting swaps the sockets without waiting for the old one to fail")
    func reconnectNow() async {
        let sockets = Sockets()
        let stream = make(["BTC"], sockets)
        await stream.start()
        _ = await nextEvent(of: stream) { $0 == .live(["BTC"], true) }
        await stream.reconnect()
        _ = await nextEvent(of: stream) { $0 == .live(["BTC"], true) }
        await stream.stop()
        #expect(sockets.count == 2)
        #expect(sockets.all.allSatisfy { $0.closed })
    }
}

struct StreamConfigurationTests {
    @Test("A stream may outlive the short limits of a price request")
    func outlivesRequests() {
        let settings = ProxySettings(mode: .custom, address: "http://127.0.0.1:1080")
        let stream = settings.streamConfiguration()
        #expect(stream.timeoutIntervalForResource >= 86_400)
        #expect(stream.connectionProxyDictionary?["HTTPSProxy"] as? String == "127.0.0.1")
        #expect(stream.connectionProxyDictionary?["HTTPSPort"] as? Int == 1080)
    }
}
