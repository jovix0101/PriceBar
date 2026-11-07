import AppKit
import Foundation
import Observation
import PriceBarCore

/// What a connection test found, for the settings window to report.
struct ConnectionResult: Equatable, Sendable {
    var ok: Bool
    var text: String
}

/// The app's state, shared by the menu bar item and the panel.
///
/// Every setting the user can change is a property here, so that a view binds
/// to it directly and the store decides what a change means: save it, read
/// the prices again, restart the timer.
@MainActor
@Observable
final class Store {
    private(set) var quotes: [Quote] = []
    /// The panel's instruments the last read found no price for, and why:
    /// a code the exchange does not list, or a market out of reach. Shown
    /// as rows of their own, so that a contract does not vanish from the
    /// panel when its market cannot be reached.
    private(set) var missing: [String: PriceAPI.Absence] = [:]
    private(set) var error: String?
    /// What to do about `error`. A failed read is the one place where the
    /// source and the proxy are worth naming, because they are the two things
    /// the user can change.
    private(set) var errorHint: String?
    /// The dollar's rate in yuan. nil until it has been read, which the panel
    /// shows as "—" rather than a wrong number.
    private(set) var rate: Double?
    /// Each coin's last day of hourly closes, oldest first, drawn beside its
    /// price. Missing until the line has been read.
    private(set) var lines: [String: [Double]] = [:]
    /// The settings, stored. Every property below reads and writes here, so
    /// that one write path saves and reacts in one place.
    private var settings: AppSettings

    /// The last connection test, and whether one is running.
    private(set) var connectionTest: ConnectionResult?
    private(set) var testing = false

    /// Whether the panel is on screen. Told by the status item, whose popover
    /// knows when it opens and closes.
    private(set) var panelIsOnScreen = false

    /// Each reconnect gets a number, so a slow reset for an older proxy
    /// change cannot wipe the cooldown the new one has just earned.
    private var reconnectGeneration = 0

    /// The panel opened: it wants its lines.
    func panelOpened() {
        guard !panelIsOnScreen else { return }
        panelIsOnScreen = true
        loadLines()
    }

    func panelClosed() {
        panelIsOnScreen = false
    }

    /// The language the app is drawn in. A view reads `strings` rather than
    /// this, so it does not have to know which language it is reading.
    var language: Language {
        get { settings.language }
        set {
            let changed = settings.language != newValue
            apply { $0.language = newValue }
            if changed { languageDidChange?() }
        }
    }

    /// Called once the language has changed, for the parts of the app that
    /// are AppKit's: a menu item's title is written once and stays, so the
    /// menu bar of the app has to be built again to say its commands in the
    /// new language. The views need nothing — they read `strings` and redraw.
    @ObservationIgnored var languageDidChange: (() -> Void)?

    /// Every word the views say, in the language chosen.
    var strings: Strings { Strings(settings.language) }

    var currency: Currency {
        get { settings.currency }
        set { apply { $0.currency = newValue } }
    }

    var interval: Double {
        get { settings.interval }
        set { apply { $0.interval = newValue } }
    }

    /// How many coins the panel shows before it starts scrolling.
    var panelRows: Int {
        get { settings.panelRows }
        set { apply { $0.panelRows = newValue } }
    }

    /// Whether a click on a coin in the panel opens its contract page.
    var openContractOnClick: Bool {
        get { settings.openContractOnClick }
        set { apply { $0.openContractOnClick = newValue } }
    }

    var changeColors: ChangeColors {
        get { settings.changeColors }
        set { apply { $0.changeColors = newValue } }
    }

    var menuBarTint: MenuBarTint {
        get { settings.menuBarTint }
        set { apply { $0.menuBarTint = newValue } }
    }

    var source: MarketSource {
        get { settings.source }
        set { apply { $0.source = newValue } }
    }

    var proxyMode: ProxyMode {
        get { settings.proxyMode }
        set { apply { $0.proxyMode = newValue } }
    }

    var proxyAddress: String {
        get { settings.proxyAddress }
        set { apply { $0.proxyAddress = newValue } }
    }

    /// The coins the menu bar shows, in the order they sit there. Kept in
    /// panel order, so that reordering the panel reorders the menu bar too.
    private(set) var menuBarCoins: [String] {
        get { settings.menuBarCoins }
        set { apply { $0.menuBarCoins = newValue } }
    }

    /// Every coin the panel lists, in the order it lists them.
    private(set) var coins: [String] {
        get { settings.coins }
        set { apply { $0.coins = newValue } }
    }

    private(set) var rules: [Rule] {
        get { settings.rules }
        set { apply { $0.rules = newValue } }
    }

    /// Why the proxy address cannot be used yet, or nil when it can.
    var proxyProblem: String? {
        ProxySettings(mode: settings.proxyMode, address: settings.proxyAddress).problem(strings)
    }

    @ObservationIgnored private var engine: AlertEngine
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var refreshing = false
    /// The way out to the network: one session for the source and proxy the
    /// settings name, rebuilt when either changes.
    @ObservationIgnored private var session: URLSession
    /// When each coin's line was last read. A line is a shape, not a price:
    /// a few minutes old is still true.
    @ObservationIgnored private var linesReadAt: [String: Date] = [:]
    @ObservationIgnored private var readingLines = false

    /// The held connections the exchange pushes prices over. Only an app that has
    /// started opens one: a preview or a test never touches the network.
    @ObservationIgnored private var stream: PriceStream?
    @ObservationIgnored private var streamEvents: Task<Void, Never>?
    @ObservationIgnored private var started = false
    /// The coins whose connection is open now. Polling leaves them alone.
    @ObservationIgnored private var live: Set<String> = []
    /// When each coin's price last arrived, by either road.
    @ObservationIgnored private var seen: [String: Date] = [:]
    /// When the exchange last said it does not list a coin.
    @ObservationIgnored private var notListedAt: [String: Date] = [:]
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?

    /// Loads the settings the app remembers. A preview, or a test, gives them
    /// its own, with prices to show and no network behind them.
    init(
        settings: AppSettings = .load(),
        quotes: [Quote] = [],
        rate: Double? = nil,
        error: String? = nil,
        lines: [String: [Double]] = [:],
        missing: [String: PriceAPI.Absence] = [:]
    ) {
        self.settings = settings
        self.quotes = quotes
        self.missing = missing
        self.rate = rate
        self.error = error
        self.lines = lines
        self.engine = AlertEngine(rules: settings.rules)
        self.session = ProxySettings(mode: settings.proxyMode, address: settings.proxyAddress).session()
    }

    // MARK: - What the views read

    /// Whether any instrument on the panel is a contract: the panel then
    /// makes room for the tag that says so.
    var hasContracts: Bool {
        coins.contains { Instrument(id: $0).market == .perpetual }
    }

    /// The coins the menu bar has to show, in the order the panel lists them.
    /// A coin whose price has not arrived is skipped rather than shown blank.
    var menuBarQuotes: [Quote] {
        let found = menuBarCoins.compactMap { coin in quotes.first { $0.coin == coin } }
        if !found.isEmpty { return found }
        // Nothing chosen, or nothing read yet: the first price is the one
        // worth showing.
        return Array(quotes.prefix(1))
    }

    /// The whole label as it will read in the menu bar, coin by coin: what a
    /// screen reader says.
    var menuBarReading: String {
        MenuBarPrice.reading(MenuBarPrice.labels(for: self), strings)
    }

    /// How the panel's footer names what the menu bar is showing.
    var menuBarSummary: String {
        let shown = menuBarQuotes.map { Instrument(id: $0.coin).code }
        guard !shown.isEmpty else { return strings.menuBarSummaryEmpty }
        return strings.menuBarSummary(shown.joined(separator: strings.listSeparator))
    }

    func isOnMenuBar(_ coin: String) -> Bool {
        menuBarCoins.contains(coin)
    }

    /// Adds a coin to the menu bar, or takes it off. Taking the last one off
    /// is allowed: the menu bar falls back to the first price rather than
    /// refusing the click.
    func toggleMenuBar(_ coin: String) {
        menuBarCoins = CoinOrder.toggling(coin, panel: coins, menuBar: menuBarCoins)
    }

    /// Drops a coin onto another. One order for both places: the panel lists
    /// the coins in it, and the menu bar puts the chosen ones in it.
    func moveCoin(_ coin: String, onto target: String) {
        coins = CoinOrder.moving(coin, onto: target, in: coins)
    }

    /// Opens the exchange's own page for this coin, in the browser. On the
    /// source the prices come from, so the page shows the market the number
    /// beside it was read from rather than another exchange's.
    func openContract(for coin: String) {
        guard let page = source.contractPage(
            for: Instrument(id: coin).code, language: language
        ) else { return }
        NSWorkspace.shared.open(page)
    }

    /// The rate to show a price in the chosen currency, or nil while the rate
    /// the user asked for has not arrived.
    var displayRate: Double? {
        currency == .cny ? rate : 1
    }

    /// A price in the chosen currency, symbol and all, for the one place
    /// that draws a single run of text: the menu bar.
    func money(_ price: Double) -> String {
        guard let displayRate else { return currency.symbol + "—" }
        return formatMoney(price * displayRate, currency: currency)
    }

    /// The same price without its symbol, for the panel, which draws the
    /// symbol smaller than the digits beside it.
    func amount(_ price: Double) -> String {
        guard let displayRate else { return "—" }
        return formatPrice(price * displayRate)
    }

    /// Reads the lines for coins whose line is missing or older than a few
    /// minutes. Called as the panel opens, so that a panel left closed costs
    /// nothing.
    func loadLines(force: Bool = false) {
        guard !readingLines else { return }
        let stale = coins.filter { coin in
            if force { return true }
            guard let readAt = linesReadAt[coin] else { return true }
            return Date().timeIntervalSince(readAt) > 300
        }
        guard !stale.isEmpty else { return }

        let source = source
        let session = session
        readingLines = true
        Task {
            defer { readingLines = false }
            for coin in stale {
                guard let closes = try? await PriceAPI.closes(coin: coin, source: source, session: session),
                      closes.count > 1
                else { continue }
                lines[coin] = closes
                linesReadAt[coin] = Date()
            }
        }
    }

    // MARK: - Reading prices

    func start() {
        guard !started else { return }
        started = true
        // Read the rate first, so that a panel in yuan shows numbers rather
        // than dashes from the first frame with prices in it.
        Task {
            await loadRate()
            refresh(all: true)
        }
        schedule()
        openStream()
        // A Mac that slept has a connection that only looks open.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.woke() }
        }
    }

    // MARK: - Pushed prices

    /// Opens the connection for the coins on the panel, in place of any
    /// connection already open. A source that does not push is polled only.
    private func openStream() {
        closeStream()
        guard started, source.pushesPrices, proxyProblem == nil, !coins.isEmpty else { return }
        let stream = PriceStream(
            source: source,
            instruments: coins.map(Instrument.init(id:)),
            proxy: ProxySettings(mode: settings.proxyMode, address: settings.proxyAddress)
        )
        self.stream = stream
        streamEvents = Task { [weak self] in
            await stream.start()
            for await event in stream.events {
                self?.receive(event, from: stream)
            }
        }
    }

    private func closeStream() {
        streamEvents?.cancel()
        streamEvents = nil
        live.removeAll()
        if let old = stream {
            stream = nil
            Task { await old.stop() }
        }
    }

    private func receive(_ event: PriceStream.Event, from source: PriceStream) {
        guard source === stream else { return }
        switch event {
        case let .live(ids, up):
            if up { live.formUnion(ids) } else { live.subtract(ids) }
        case let .quotes(incoming):
            let now = Date()
            for quote in incoming {
                seen[quote.coin] = now
                notListedAt[quote.coin] = nil
            }
            (quotes, missing) = ReadPlan.pushed(incoming, coins: coins, quotes: quotes, missing: missing)
            error = nil
            errorHint = nil
            checkAlerts(incoming)
        }
    }

    private func woke() {
        guard let stream else { return }
        live.removeAll()
        Task { await stream.reconnect() }
        refresh(all: true)
    }

    private func loadRate() async {
        guard rate == nil else { return }
        rate = try? await FXAPI.usdToCNY(session: session)
    }

    private func schedule() {
        timer?.invalidate()
        let every = max(3, interval)
        timer = Timer.scheduledTimer(withTimeInterval: every, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    /// Reads prices over HTTP. The timer asks only about coins the
    /// connection is not covering; the refresh button, `all`, asks about
    /// every coin once.
    func refresh(all: Bool = false) {
        guard !refreshing else { return }
        if let problem = proxyProblem {
            error = problem
            errorHint = nil
            return
        }

        let coins = coins
        let live = all ? [] : self.live
        let asked = ReadPlan.coins(coins, live: live, seen: seen, notListed: notListedAt, now: Date())
        guard !asked.isEmpty else { return }

        refreshing = true
        let source = source
        let session = session
        let generation = reconnectGeneration

        Task {
            defer { refreshing = false }
            let reading = await PriceAPI.read(
                asked, source: source, session: session, strings: self.strings
            )
            // Settings changed while this read was out: its answer is about
            // a source or a proxy that is no longer in use.
            guard generation == self.reconnectGeneration else { return }
            let live = self.live
            // Nothing came back, something was out of reach, and no
            // connection is carrying prices: the source or the proxy is the
            // problem, and the prices in hand are kept rather than wiped for
            // a blank panel.
            if reading.quotes.isEmpty, let reason = reading.unreachable, live.isDisjoint(with: coins) {
                self.error = self.strings.sourceProblem(source.label, reason)
                self.errorHint = self.isRateLimit(reading)
                    ? self.strings.rateLimitedHint
                    : self.hint(for: source, market: self.unreachableMarket(in: reading))
                return
            }
            let now = Date()
            for quote in reading.quotes { self.seen[quote.coin] = now }
            for (coin, why) in reading.missing where why == .notListed { self.notListedAt[coin] = now }
            (self.quotes, self.missing) = ReadPlan.merged(
                coins: self.coins, asked: asked, reading: reading,
                quotes: self.quotes, missing: self.missing, live: live
            )
            self.error = nil
            self.errorHint = nil
            self.checkAlerts(reading.quotes)
        }
    }

    /// A limit is not a broken proxy. The usual hint tells the user to go
    /// check the proxy; changing it would clear the cooldown and walk
    /// straight back into a ban that is still running.
    private func isRateLimit(_ reading: PriceAPI.Reading) -> Bool {
        reading.missing.values.contains { why in
            guard case let .unreachable(message) = why else { return false }
            return message.contains("HTTP 429") || message.contains("HTTP 418")
        }
    }

    /// The market a read could not reach, for the hint: Binance's contracts
    /// want a proxy where its spot prices do not.
    private func unreachableMarket(in reading: PriceAPI.Reading) -> Market {
        let ids = reading.missing.compactMap { id, why in
            if case .unreachable = why { return id }
            return nil
        }
        return ids.allSatisfy { Instrument(id: $0).market == .perpetual } ? .perpetual : .spot
    }

    /// What to try next, said in terms of the two things the user can change.
    func hint(for source: MarketSource, market: Market = .spot) -> String {
        let strings = self.strings
        switch settings.proxyMode {
        case .custom:
            return strings.checkProxyRunning(settings.proxyAddress)
        case .direct, .system:
            if source.normallyNeedsProxy(for: market) {
                let what = market == .perpetual && !source.normallyNeedsProxy
                    ? strings.sourceContracts(source.label)
                    : source.label
                return strings.needsProxyTurnOn(what)
            }
            return strings.tryAnotherSource
        }
    }

    /// Reads one instrument of each market on the panel through the current
    /// source and proxy, and reports what came back: the one way to tell a
    /// blocked source from a wrong address. Both markets are tried when both
    /// are in use, because Binance's contracts can be blocked where its spot
    /// prices are not.
    func testConnection() {
        if let problem = proxyProblem {
            connectionTest = ConnectionResult(ok: false, text: problem)
            return
        }
        guard !testing else { return }

        testing = true
        connectionTest = nil
        let source = source
        let session = session
        let instruments = coins.map(Instrument.init(id:))
        var probes = Market.allCases.compactMap { market in
            instruments.first { $0.market == market }?.id
        }
        if probes.isEmpty { probes = ["BTC"] }
        let started = Date()

        Task {
            defer { testing = false }
            let strings = self.strings
            let reading = await PriceAPI.read(
                probes, source: source, session: session, strings: strings
            )
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            let parts = probes.map { id -> (ok: Bool, text: String) in
                let instrument = Instrument(id: id)
                let name = probes.count > 1
                    ? "\(instrument.market.label(strings)) \(instrument.code)"
                    : instrument.code
                if let quote = reading.quotes.first(where: { $0.coin == id }) {
                    return (true, "\(name) \(money(quote.price))")
                }
                switch reading.missing[id] {
                case let .unreachable(message)? where live.contains(id):
                    // The prices on the panel come over the connection; a
                    // limit on the HTTP side does not stop them.
                    return (true, strings.liveButReadFailed(name, message))
                case let .unreachable(message)?:
                    return (false, strings.failedPart(name, message))
                default:
                    return (false, strings.answeredNoQuote(name))
                }
            }
            let ok = parts.allSatisfy(\.ok)
            let head = ok ? strings.sourceOK(source.label, ms) : source.label
            connectionTest = ConnectionResult(
                ok: ok,
                text: ([head] + parts.map(\.text)).joined(separator: " · ")
            )
        }
    }

    private func checkAlerts(_ quotes: [Quote]) {
        let alerts = engine.evaluate(quotes)
        guard !alerts.isEmpty else { return }
        // The engine owns the armed flags, so store what it decided.
        rules = engine.rules
        for alert in alerts {
            Notifier.send(
                title: alert.title(strings),
                body: alert.body(strings, currency: currency, rate: displayRate ?? 1)
            )
        }
    }

    // MARK: - Coins

    /// Asks the exchange which of its markets list a code, and decides what
    /// the add popover should do with it.
    func lookUp(_ raw: String) async -> CoinValidation.Decision {
        let strings = self.strings
        let code = CoinValidation.normalize(raw)
        if let problem = CoinValidation.problem(coin: code, existing: coins, strings: strings) {
            return .problem(problem)
        }
        let reading = await PriceAPI.lookUp(
            code: code, source: source, session: session, strings: strings
        )
        return CoinValidation.decide(
            code: code, existing: coins, reading: reading, source: source, strings: strings
        )
    }

    /// Adds instruments the exchange has said it lists, at the end of the
    /// panel, spot before contract.
    func add(_ instruments: [Instrument]) {
        let new = instruments.map(\.id).filter { !coins.contains($0) }
        guard !new.isEmpty else { return }
        coins.append(contentsOf: new)
    }

    func removeCoin(_ coin: String) {
        coins.removeAll { $0 == coin }
        rules.removeAll { $0.coin == coin }
        missing[coin] = nil
        lines[coin] = nil
        linesReadAt[coin] = nil
        seen[coin] = nil
        notListedAt[coin] = nil
    }

    // MARK: - Rules

    func rules(for coin: String) -> [Rule] {
        rules.filter { $0.coin == coin }
    }

    func addRule(_ rule: Rule) {
        rules.append(rule)
        engine = AlertEngine(rules: rules)
    }

    func removeRule(_ id: UUID) {
        rules.removeAll { $0.id == id }
        engine = AlertEngine(rules: rules)
    }

    /// Re-arms a rule the user has already seen fire.
    func rearm(_ id: UUID) {
        guard let index = rules.firstIndex(where: { $0.id == id }) else { return }
        rules[index].armed = true
        engine = AlertEngine(rules: rules)
    }

    // MARK: - Writing settings

    /// Changes the settings, then does what the change asks for: a new coin
    /// is shown at once, a new interval restarts the timer, a new source or
    /// proxy opens a new way to the network, and everything is saved.
    private func apply(_ change: (inout AppSettings) -> Void) {
        let before = settings
        var after = settings
        change(&after)
        // A coin taken off the panel takes its menu bar place with it, and a
        // reordering of the panel is a reordering of the menu bar.
        after.menuBarCoins = CoinOrder.settled(after.menuBarCoins, panel: after.coins)
        guard after != before else { return }
        settings = after
        after.save()

        // Reordering is not a new set of coins: nothing has to be read again.
        let reread = Set(after.coins) != Set(before.coins)
        // Only a new proxy means a new exit IP. A different exchange has
        // its own cooldown slot, so switching there must not forget a ban
        // that is still running on this one.
        let proxyChanged = after.proxyMode != before.proxyMode
            || after.proxyAddress != before.proxyAddress
        let reconnect = after.source != before.source || proxyChanged
        let reschedule = after.interval != before.interval
        let needRate = after.currency == .cny && rate == nil

        // A reordering is not a reason to wait for the next read: the prices
        // in hand are put in the new order now, so the panel moves when the
        // coin does.
        if after.coins != before.coins {
            quotes = after.coins.compactMap { coin in quotes.first { $0.coin == coin } }
        }

        if reconnect {
            reconnectGeneration += 1
            session = ProxySettings(mode: after.proxyMode, address: after.proxyAddress).session()
            // A day of candles from another exchange is another shape.
            lines.removeAll()
            linesReadAt.removeAll()
            missing.removeAll()
            seen.removeAll()
            notListedAt.removeAll()
            connectionTest = nil
        }
        // A connection carries a fixed set of coins from one source, the
        // way the proxy settings said when it opened.
        if (reconnect || reread) && !proxyChanged { openStream() }
        if proxyChanged { closeStream() }
        if reschedule { schedule() }
        if needRate { Task { await loadRate() } }

        if proxyChanged {
            // A different proxy is a different exit IP: the old ban says
            // nothing about it. Clear the cooldown before asking anything,
            // including the candles a panel already open wants again.
            let generation = reconnectGeneration
            Task { @MainActor in
                guard generation == self.reconnectGeneration else { return }
                await RequestPacing.shared.reset()
                guard generation == self.reconnectGeneration else { return }
                openStream()
                if panelIsOnScreen { loadLines(force: true) }
                refresh(all: true)
            }
        } else if reread || reconnect {
            refresh()
        }
    }
}
