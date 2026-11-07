import Foundation
import Testing
@testable import PriceBarCore

/// Binance limits request weight per IP, not per key: the wait after a 429
/// or a 418 has to be long enough for a shared proxy exit address to clear.
/// The numbers here follow the exchange's own limits document: Retry-After
/// is the authority, bans start at two minutes, and the weight window is a
/// minute long.
struct RequestPacingTests {

    struct WaitCase: Sendable {
        let code: Int
        let retryAfter: String?
        let streak: Int
        let expected: Int
        let why: String
    }

    static let cases: [WaitCase] = [
        .init(code: 429, retryAfter: nil, streak: 0, expected: 60,
              why: "no header: a whole one-minute weight window"),
        .init(code: 429, retryAfter: "5", streak: 0, expected: 30,
              why: "a five-second header is too short on a shared exit IP"),
        .init(code: 429, retryAfter: "45", streak: 0, expected: 45,
              why: "a longer header is honoured as written"),
        .init(code: 429, retryAfter: "45", streak: 1, expected: 90,
              why: "a second violation doubles the header's wait"),
        .init(code: 429, retryAfter: nil, streak: 1, expected: 120, why: "429 backs off"),
        .init(code: 429, retryAfter: nil, streak: 2, expected: 240, why: "429 backs off"),
        .init(code: 429, retryAfter: nil, streak: 3, expected: 300, why: "429 caps at five minutes"),
        .init(code: 429, retryAfter: nil, streak: 9, expected: 300, why: "429 caps at five minutes"),
        .init(code: 429, retryAfter: "259200", streak: 0, expected: 300,
              why: "429 governs a one-minute weight window, never days"),
        .init(code: 418, retryAfter: nil, streak: 0, expected: 120,
              why: "the shortest IP ban Binance documents is two minutes"),
        .init(code: 418, retryAfter: "120", streak: 0, expected: 120, why: "418 honours the header"),
        .init(code: 418, retryAfter: "45", streak: 0, expected: 120,
              why: "a ban shorter than two minutes still gets two minutes"),
        .init(code: 418, retryAfter: nil, streak: 1, expected: 240, why: "418 backs off"),
        .init(code: 418, retryAfter: nil, streak: 4, expected: 1800,
              why: "418 caps at thirty minutes"),
        .init(code: 418, retryAfter: "259200", streak: 0, expected: 259_200,
              why: "a three-day ban is waited out, not probed early"),
        .init(code: 418, retryAfter: "600", streak: 3, expected: 600,
              why: "Retry-After already accounts for repeat offences"),
    ]

    @Test("The wait follows Retry-After and backs off on repeat violations",
          arguments: cases)
    func waitSeconds(_ c: WaitCase) {
        #expect(RequestPacing.waitSeconds(
            code: c.code, retryAfter: c.retryAfter, consecutive: c.streak
        ) == c.expected, "\(c.why)")
    }

    @Test("A nonsense Retry-After falls back to the code's own wait")
    func nonsenseHeader() {
        #expect(RequestPacing.waitSeconds(code: 429, retryAfter: "soon", consecutive: 0) == 60)
        #expect(RequestPacing.waitSeconds(code: 418, retryAfter: "-3", consecutive: 0) == 120)
        #expect(RequestPacing.waitSeconds(code: 429, retryAfter: " 45 ", consecutive: 0) == 45)
    }

    @Test("A limited source waits, other exchanges keep working, and success clears it")
    func cooldownLifecycle() async {
        let clock = Clock(Date(timeIntervalSince1970: 1_000_000))
        let pacing = RequestPacing(now: { clock.now() })
        let host = "binance"

        #expect(await pacing.decision(for: host) == .proceed)
        let seconds = await pacing.limited(host: host, code: 429, retryAfter: nil)
        #expect(seconds == 60)
        #expect(await pacing.decision(for: host) == .wait(seconds: 60, code: 429))
        #expect(await pacing.decision(for: "gate") == .proceed)

        clock.advance(59)
        #expect(await pacing.decision(for: host) == .wait(seconds: 1, code: 429))
        clock.advance(1)
        #expect(await pacing.decision(for: host) == .proceed)

        // Still on the second strike until something actually succeeds.
        #expect(await pacing.limited(host: host, code: 429, retryAfter: nil) == 120)
        clock.advance(121)
        let sentAt = await pacing.stamp()
        await pacing.succeeded(host: host, sentAt: sentAt)
        #expect(await pacing.limited(host: host, code: 429, retryAfter: nil) == 60)
        #expect(await pacing.decision(for: host) == .wait(seconds: 60, code: 429))
    }

    @Test("A 418 remembers its own code and waits out the whole ban")
    func banIsDistinct() async {
        let pacing = RequestPacing()
        let host = "binance"
        let seconds = await pacing.limited(host: host, code: 418, retryAfter: "259200")
        #expect(seconds == 259_200)
        #expect(await pacing.decision(for: host) == .wait(seconds: 259_200, code: 418))
    }

    @Test("A late 200 from the old wave cannot clear a fresh limit")
    func lateSuccessDoesNotClearCooldown() async {
        let clock = Clock(Date(timeIntervalSince1970: 1_000_000))
        let pacing = RequestPacing(now: { clock.now() })
        let host = "binance"

        let sentAt = await pacing.stamp()                                      // a request goes out
        _ = await pacing.limited(host: host, code: 418, retryAfter: nil)        // a sibling says: banned
        await pacing.succeeded(host: host, sentAt: sentAt)                      // the 200 arrives last

        #expect(await pacing.decision(for: host) == .wait(seconds: 120, code: 418))
    }

    @Test("A weaker answer arriving late cannot shorten a ban or downgrade it")
    func weakerAnswerDoesNotShortenCooldown() async {
        let clock = Clock(Date(timeIntervalSince1970: 1_000_000))
        let pacing = RequestPacing(now: { clock.now() })
        let host = "binance"

        #expect(await pacing.limited(host: host, code: 418, retryAfter: "600") == 600)
        #expect(await pacing.limited(host: host, code: 429, retryAfter: "5") == 600)
        #expect(await pacing.decision(for: host) == .wait(seconds: 600, code: 418))
    }

    @Test("Parallel answers from one refresh count as one violation")
    func oneWaveCountsAsOneViolation() async {
        let clock = Clock(Date(timeIntervalSince1970: 1_000_000))
        let pacing = RequestPacing(now: { clock.now() })
        let host = "binance"

        // Two contracts are read at once and both get the same 429. That is
        // one wave, not two separate refusals to back off.
        #expect(await pacing.limited(host: host, code: 429, retryAfter: nil) == 60)
        #expect(await pacing.limited(host: host, code: 429, retryAfter: nil) == 60)
        #expect(await pacing.decision(for: host) == .wait(seconds: 60, code: 429))

        // A wave after the cooldown really is a repeat violation.
        clock.advance(61)
        #expect(await pacing.limited(host: host, code: 429, retryAfter: nil) == 120)

        // A ban in the same wave is more serious than the warning before it.
        await pacing.reset()
        #expect(await pacing.limited(host: host, code: 429, retryAfter: nil) == 60)
        #expect(await pacing.limited(host: host, code: 418, retryAfter: nil) == 120)
        #expect(await pacing.decision(for: host) == .wait(seconds: 120, code: 418))
    }

    @Test("Switching the proxy or the exchange ends the cooldown at once")
    func resetClearsCooldown() async {
        let pacing = RequestPacing()
        await pacing.limited(host: "binance", code: 418, retryAfter: nil)
        #expect(await pacing.decision(for: "binance") == .wait(seconds: 120, code: 418))

        // A new proxy is a new exit IP: the old ban says nothing about it.
        await pacing.reset()
        #expect(await pacing.decision(for: "binance") == .proceed)
        #expect(await pacing.limited(host: "binance", code: 429, retryAfter: nil) == 60)
    }

    @Test("The reason shown says what is happening and how long it lasts")
    func wording() {
        let english = describe(PriceError.rateLimited(code: 429, seconds: 60))
        #expect(english.contains("429"))
        #expect(english.contains("1 minute"))

        let chinese = describe(PriceError.rateLimited(code: 418, seconds: 120), Strings(.chinese))
        #expect(chinese.contains("418"))
        #expect(chinese.contains("2 分钟"))
        #expect(!chinese.contains("HTTP 418."))

        // A three-day ban is not shown as 259200 seconds.
        let longBan = describe(PriceError.rateLimited(code: 418, seconds: 259_200), Strings(.chinese))
        #expect(longBan.contains("3 天"))
        #expect(!longBan.contains("259200"))
    }
}

/// A clock whose now the tests can move, so a two-minute wait does not take
/// two minutes to check.
private final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(_ value: Date) { self.value = value }

    func now() -> Date {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    func advance(_ seconds: TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        value += seconds
    }
}

/// Answers every request with a canned status, and counts them. A request
/// that must not be sent is the whole point of a cooldown.
private final class Reply: @unchecked Sendable {
    private let lock = NSLock()
    private var status: Int
    private var retryAfter: String?
    private var hosts: [String]

    init() {
        status = 429
        retryAfter = "5"
        hosts = []
    }

    func reset(status: Int, retryAfter: String?) {
        lock.lock(); defer { lock.unlock() }
        self.status = status
        self.retryAfter = retryAfter
        hosts = []
    }

    func record(_ host: String) -> (status: Int, retryAfter: String?) {
        lock.lock(); defer { lock.unlock() }
        hosts.append(host)
        return (status, retryAfter)
    }

    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return hosts.count
    }
}

private final class StubProtocol: URLProtocol, @unchecked Sendable {
    static let reply = Reply()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let host = request.url?.host ?? ""
        let answer = Self.reply.record(host)
        var fields: [String: String] = [:]
        if let retryAfter = answer.retryAfter { fields["Retry-After"] = retryAfter }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: answer.status,
            httpVersion: "HTTP/1.1", headerFields: fields
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func stubSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubProtocol.self]
    return URLSession(configuration: configuration)
}

@Suite(.serialized)
struct PacingNetworkTests {

    @Test("After a 429 the next refresh sends nothing while cooling down")
    func noRequestsDuringCooldown() async {
        StubProtocol.reply.reset(status: 429, retryAfter: "5")
        let session = stubSession()
        let pacing = RequestPacing()
        let strings = Strings(.chinese)

        let first = await PriceAPI.read(
            ["BTC.P"], source: .binance, session: session, strings: strings, pacing: pacing
        )
        #expect(StubProtocol.reply.count == 1)
        if case let .unreachable(reason)? = first.missing["BTC.P"] {
            #expect(reason.contains("429"))
            #expect(reason.contains("30"))
        } else {
            Issue.record("The first 429 should say it is backing off")
        }

        let second = await PriceAPI.read(
            ["BTC.P"], source: .binance, session: session, strings: strings, pacing: pacing
        )
        #expect(StubProtocol.reply.count == 1, "a cooling host must not be hit again")
        if case let .unreachable(reason)? = second.missing["BTC.P"] {
            #expect(reason.contains("秒"))
        } else {
            Issue.record("The cooldown should still explain itself")
        }
    }

    @Test("A 418 answers with the ban's own code and waits at least two minutes")
    func banFromTheExchange() async {
        StubProtocol.reply.reset(status: 418, retryAfter: nil)
        let session = stubSession()
        let pacing = RequestPacing()
        let strings = Strings(.chinese)

        let reading = await PriceAPI.read(
            ["BTC.P"], source: .binance, session: session, strings: strings, pacing: pacing
        )
        if case let .unreachable(reason)? = reading.missing["BTC.P"] {
            #expect(reason.contains("418"))
            #expect(reason.contains("2 分钟"))
        } else {
            Issue.record("A 418 should say the IP is banned and for how long")
        }
        #expect(await pacing.decision(for: "binance") == .wait(seconds: 120, code: 418))
    }

    @Test("The spot batch and the candle read respect the same cooldown")
    func batchAndCandlesRespectCooldown() async {
        StubProtocol.reply.reset(status: 200, retryAfter: nil)
        let session = stubSession()
        let pacing = RequestPacing()
        // One exit IP for the whole exchange: a ban seen on the contracts
        // host stops the spot batch and the candle read too.
        await pacing.limited(host: "binance", code: 418, retryAfter: nil)

        let batch = await PriceAPI.read(
            ["BTC", "ETH"], source: .binance, session: session, pacing: pacing
        )
        #expect(batch.quotes.isEmpty)
        #expect(StubProtocol.reply.count == 0)

        do {
            _ = try await PriceAPI.closes(
                coin: "BTC.P", source: .binance, session: session, pacing: pacing
            )
            Issue.record("A cooling host should not be asked for candles")
        } catch {
            #expect(error.localizedDescription.contains("418"))
        }
        #expect(StubProtocol.reply.count == 0)
    }

    @Test("A 429 ends the host fallback instead of asking the next host")
    func limitStopsHostFallback() async {
        StubProtocol.reply.reset(status: 429, retryAfter: nil)
        let session = stubSession()
        let pacing = RequestPacing()

        // Binance spot has two host names, but one exit IP. Swapping the
        // name is not a way around a warning to back off.
        _ = await PriceAPI.read(["BTC"], source: .binance, session: session, pacing: pacing)
        #expect(StubProtocol.reply.count == 1)
        #expect(await pacing.decision(for: "binance") == .wait(seconds: 60, code: 429),
                "every host of the source shares the one cooldown")
    }

    @Test("A success clears the cooldown and the ordinary polls continue")
    func successClearsCooldown() async {
        StubProtocol.reply.reset(status: 200, retryAfter: nil)
        let clock = Clock(Date())
        let session = stubSession()
        let pacing = RequestPacing(now: { clock.now() })
        await pacing.limited(host: "binance", code: 429, retryAfter: nil)
        clock.advance(61)

        // The canned 200 has no ticker body, so the read reports the coin as
        // not listed — but the HTTP answer still came back, which is what
        // clears a rate limit.
        _ = await PriceAPI.read(["BTC.P"], source: .binance, session: session, pacing: pacing)
        #expect(StubProtocol.reply.count == 1)
        #expect(await pacing.decision(for: "binance") == .proceed)
    }
}
