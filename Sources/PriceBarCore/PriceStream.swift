import Foundation

/// A connection that delivers text, stated small enough to fake in a test.
public protocol PriceSocket: AnyObject, Sendable {
    func open()
    func receive() async throws -> String
    func send(_ text: String) async throws
    /// `done` hears whether the far end answered; it may never be called.
    func ping(_ done: @escaping @Sendable (Bool) -> Void)
    func close()
    /// The status that refused the handshake, once the connection has failed.
    var refusal: (code: Int, retryAfter: String?)? { get }
}

/// A `URLSessionWebSocketTask`. It answers the exchange's own pings by itself.
final class WebSocketConnection: PriceSocket {
    private let task: URLSessionWebSocketTask

    init(task: URLSessionWebSocketTask) { self.task = task }

    func open() { task.resume() }

    func receive() async throws -> String {
        switch try await task.receive() {
        case let .string(text): return text
        case let .data(data): return String(decoding: data, as: UTF8.self)
        @unknown default: return ""
        }
    }

    func send(_ text: String) async throws {
        try await task.send(.string(text))
    }

    func ping(_ done: @escaping @Sendable (Bool) -> Void) {
        task.sendPing { error in done(error == nil) }
    }

    func close() { task.cancel(with: .goingAway, reason: nil) }

    var refusal: (code: Int, retryAfter: String?)? {
        guard let http = task.response as? HTTPURLResponse, http.statusCode != 101 else { return nil }
        return (http.statusCode, http.value(forHTTPHeaderField: "Retry-After"))
    }
}

/// Holds one connection per market and hands the prices over as they change.
///
/// Pushed prices use no request weight, which is what keeps a shared proxy
/// exit out of 429s. The limits that replace it are the exchanges' connection
/// limits: Binance allows 300 attempts per 5 minutes per IP, Bybit 500, OKX
/// 3 a second, and IPs that are repeatedly disconnected may be banned. So
/// reopening backs off, up to a minute apart, and every market shares one
/// connection.
public actor PriceStream {
    public struct Timing: Sendable {
        /// How often to ask whether the far end is still there. A quiet
        /// market sends nothing, so silence alone cannot tell.
        public var ping: TimeInterval
        /// How long without hearing anything before the connection is dead.
        public var silence: TimeInterval
        /// The shortest gap between handovers, so a busy market does not
        /// redraw the menu bar several times a second.
        public var flush: TimeInterval
        /// How long a connection must last for its loss to count as a fresh
        /// start rather than one more failure in a row.
        public var steady: TimeInterval
        /// Scales every wait between connections.
        public var retryScale: Double

        public init(
            ping: TimeInterval = 15, silence: TimeInterval = 40, flush: TimeInterval = 1,
            steady: TimeInterval = 60, retryScale: Double = 1
        ) {
            self.ping = ping
            self.silence = silence
            self.flush = flush
            self.steady = steady
            self.retryScale = retryScale
        }
    }

    public enum Event: Sendable, Equatable {
        case quotes([Quote])
        /// These instruments' connection opened (true) or was lost (false).
        case live(Set<String>, Bool)
    }

    /// The cooldown of an exchange's connections, apart from its polling's:
    /// a ban on HTTP must not stop the stream, which is where Binance's own
    /// ban message sends you. A refused handshake sets both.
    public static func pacingSlot(_ source: MarketSource) -> String {
        source.rawValue + "-stream"
    }

    public nonisolated let events: AsyncStream<Event>

    private struct Link {
        let token: UUID
        let socket: any PriceSocket
        var lastHeard: Date
        var live = false
    }

    private let wires: [StreamWire]
    private let streamSlot: String
    private let pollingSlot: String
    private let pacing: RequestPacing
    private let timing: Timing
    private let connect: @Sendable (URL) -> any PriceSocket
    private let finish: @Sendable () -> Void
    private let continuation: AsyncStream<Event>.Continuation

    private var runs: [Task<Void, Never>] = []
    private var links: [String: Link] = [:]
    private var pending: [String: Quote] = [:]
    private var flushing: Task<Void, Never>?
    private var stopped = false

    public init(
        source: MarketSource, instruments: [Instrument], pacing: RequestPacing = .shared,
        timing: Timing = Timing(), connect: @escaping @Sendable (URL) -> any PriceSocket,
        finish: @escaping @Sendable () -> Void = {}
    ) {
        wires = source.pushesPrices ? source.streamWires(for: instruments) : []
        streamSlot = Self.pacingSlot(source)
        pollingSlot = source.rawValue
        self.pacing = pacing
        self.timing = timing
        self.connect = connect
        self.finish = finish
        (events, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(64))
    }

    /// A stream that goes out the way the proxy settings say.
    public init(source: MarketSource, instruments: [Instrument], proxy: ProxySettings) {
        let session = URLSession(configuration: proxy.streamConfiguration())
        self.init(
            source: source, instruments: instruments,
            connect: { WebSocketConnection(task: session.webSocketTask(with: $0)) },
            finish: { session.invalidateAndCancel() }
        )
    }

    /// How long to wait before the next try, after failures in a row.
    static func backoff(failures: Int) -> TimeInterval {
        min(60, TimeInterval(1 << min(max(failures - 1, 0), 6)))
    }

    public func start() {
        guard runs.isEmpty, !stopped else { return }
        launch()
    }

    /// Opens everything again now. For the moments a held connection is
    /// known to have gone stale, like the Mac waking up.
    public func reconnect() async {
        guard !stopped else { return }
        await closeAll()
        guard !stopped else { return }
        launch()
    }

    public func stop() async {
        stopped = true
        flushing?.cancel()
        flushing = nil
        await closeAll()
        continuation.finish()
        finish()
    }

    private func launch() {
        runs = wires.map { wire in Task { await self.run(wire) } }
    }

    private func closeAll() async {
        let ending = runs
        runs = []
        ending.forEach { $0.cancel() }
        links.values.forEach { $0.socket.close() }
        for run in ending { await run.value }
    }

    private func run(_ wire: StreamWire) async {
        var failures = 0
        while !Task.isCancelled {
            if case let .wait(seconds, _) = await pacing.decision(for: streamSlot) {
                await pause(Double(seconds))
                continue
            }
            let lasted = await hold(wire, sentAt: await pacing.stamp())
            guard !Task.isCancelled else { return }
            failures = lasted >= timing.steady ? 1 : failures + 1
            await pause(Self.backoff(failures: failures))
        }
    }

    private func pause(_ seconds: TimeInterval) async {
        try? await Task.sleep(for: .seconds(seconds * timing.retryScale))
    }

    /// One connection, from opening to its loss. Answers how long it was up.
    private func hold(_ wire: StreamWire, sentAt: Date) async -> TimeInterval {
        let token = UUID()
        let socket = connect(wire.url)
        let opened = Date()
        links[wire.key] = Link(token: token, socket: socket, lastHeard: opened)
        socket.open()

        var reader = StreamReader(wire: wire)
        let watchdog = Task { await self.watch(wire, token: token, sentAt: sentAt) }
        do {
            for message in wire.subscriptions(at: Date()) {
                try await socket.send(message)
            }
            while !Task.isCancelled {
                let text = try await socket.receive()
                heard(wire, token: token, sentAt: sentAt)
                reader.quotes(in: text).forEach(collect)
            }
        } catch {
            if let refusal = socket.refusal, refusal.code == 429 || refusal.code == 418 {
                await pacing.limited(host: streamSlot, code: refusal.code, retryAfter: refusal.retryAfter)
                await pacing.limited(host: pollingSlot, code: refusal.code, retryAfter: refusal.retryAfter)
            }
        }
        watchdog.cancel()
        socket.close()

        var wasLive = false
        if let link = links[wire.key], link.token == token {
            wasLive = link.live
            links[wire.key] = nil
        }
        if wasLive { continuation.yield(.live(wire.ids, false)) }
        return wasLive ? Date().timeIntervalSince(opened) : 0
    }

    /// Pings for as long as the connection is this one, and closes it when
    /// nothing has come back for too long: a Mac asleep, or a proxy that
    /// dropped the tunnel, leaves a socket that never reports an error.
    /// Exchanges that close a quiet connection get their own heartbeat as
    /// well, whose answer arrives as an ordinary message.
    private func watch(_ wire: StreamWire, token: UUID, sentAt: Date) async {
        while !Task.isCancelled {
            guard let link = links[wire.key], link.token == token else { return }
            if Date().timeIntervalSince(link.lastHeard) > timing.silence {
                link.socket.close()
                return
            }
            link.socket.ping { [weak self] answered in
                guard answered, let self else { return }
                Task { await self.heard(wire, token: token, sentAt: sentAt) }
            }
            if link.live, let beat = wire.heartbeat(at: Date()) {
                let socket = link.socket
                Task { try? await socket.send(beat) }
            }
            try? await Task.sleep(for: .seconds(timing.ping))
        }
    }

    private func heard(_ wire: StreamWire, token: UUID, sentAt: Date) {
        guard var link = links[wire.key], link.token == token else { return }
        link.lastHeard = Date()
        let opening = !link.live
        link.live = true
        links[wire.key] = link
        guard opening else { return }
        // Exchanges that close a quiet connection get their first heartbeat as
        // soon as the link is live, not one tick later: on a loaded machine a
        // single tick can already be longer than the silence window.
        if let beat = wire.heartbeat(at: Date()) {
            let socket = link.socket
            Task { try? await socket.send(beat) }
        }
        continuation.yield(.live(wire.ids, true))
        let pacing = pacing
        let slot = streamSlot
        Task { await pacing.succeeded(host: slot, sentAt: sentAt) }
    }

    /// Keeps the newest price of each coin, and hands them over together.
    private func collect(_ quote: Quote) {
        pending[quote.coin] = quote
        guard flushing == nil else { return }
        flushing = Task {
            try? await Task.sleep(for: .seconds(timing.flush))
            self.flush()
        }
    }

    private func flush() {
        flushing = nil
        guard !stopped, !pending.isEmpty else { return }
        continuation.yield(.quotes(Array(pending.values)))
        pending.removeAll()
    }
}
