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

    /// Which of the menu bar coins is showing right now.
    private(set) var rotationIndex = 0
    /// Whether the panel is on screen. Told by the status item, whose popover
    /// knows when it opens and closes.
    private(set) var panelIsOnScreen = false

    /// The panel opened: it wants its lines, and the menu bar holds still
    /// while it is being read.
    func panelOpened() {
        guard !panelIsOnScreen else { return }
        panelIsOnScreen = true
        loadLines()
    }

    /// The panel closed: the menu bar takes turns again, starting from the
    /// first coin, so that it always opens on the same one it closed with.
    func panelClosed() {
        guard panelIsOnScreen else { return }
        panelIsOnScreen = false
        rotationIndex = 0
    }

    var currency: Currency {
        get { settings.currency }
        set { apply { $0.currency = newValue } }
    }

    var interval: Double {
        get { settings.interval }
        set { apply { $0.interval = newValue } }
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

    /// The coins the menu bar takes turns showing, in panel order.
    private(set) var menuBarCoins: [String] {
        get { settings.menuBarCoins }
        set { apply { $0.menuBarCoins = newValue } }
    }

    var rotateInterval: Double {
        get { settings.rotateInterval }
        set { apply { $0.rotateInterval = newValue } }
    }

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
        ProxySettings(mode: settings.proxyMode, address: settings.proxyAddress).problem
    }

    @ObservationIgnored private var engine: AlertEngine
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var rotateTimer: Timer?
    @ObservationIgnored private var refreshing = false
    /// The way out to the network: one session for the source and proxy the
    /// settings name, rebuilt when either changes.
    @ObservationIgnored private var session: URLSession
    /// When each coin's line was last read. A line is a shape, not a price:
    /// a few minutes old is still true.
    @ObservationIgnored private var linesReadAt: [String: Date] = [:]
    @ObservationIgnored private var readingLines = false

    /// Loads the settings the app remembers. A preview, or a test, gives them
    /// its own, with prices to show and no network behind them.
    init(settings: AppSettings = .load(), quotes: [Quote] = [], rate: Double? = nil, error: String? = nil) {
        self.settings = settings
        self.quotes = quotes
        self.rate = rate
        self.error = error
        self.engine = AlertEngine(rules: settings.rules)
        self.session = ProxySettings(mode: settings.proxyMode, address: settings.proxyAddress).session()
    }

    // MARK: - What the views read

    /// The coins the menu bar has to show, in the order the panel lists them.
    /// A coin whose price has not arrived is skipped rather than shown blank.
    var menuBarQuotes: [Quote] {
        let found = menuBarCoins.compactMap { coin in quotes.first { $0.coin == coin } }
        if !found.isEmpty { return found }
        // Nothing chosen, or nothing read yet: the first price is the one
        // worth showing.
        return Array(quotes.prefix(1))
    }

    /// The price the menu bar shows this second.
    var menuBarQuote: Quote? {
        let list = menuBarQuotes
        guard !list.isEmpty else { return nil }
        return list[rotationIndex % list.count]
    }

    /// The widest label the menu bar has to draw, so that the item keeps one
    /// width while coins take turns. Read off the prices in hand; a coin whose
    /// price has not arrived is measured at the widest price it could have,
    /// which is the one already showing.
    ///
    /// This is the width of the drawn part alone. The change rides beside it
    /// as the item's title and brings its own width with it, which is the same
    /// for every coin, since an empty change is still reserved at full size.
    var menuBarWidth: CGFloat {
        let labels = menuBarQuotes.map { quote in
            MenuBarPrice.width(of: MenuBarPrice.Label(
                coin: quote.coin,
                symbol: currency.symbol,
                amount: amount(quote.price),
                change: MenuBarPrice.widthReserve(quote.change),
                changeValue: quote.change
            ))
        }
        return labels.max() ?? 0
    }

    /// How much room the drawn price leaves unused this second.
    ///
    /// The item is as wide as the widest coin on its list, so a narrower price
    /// would otherwise leave its change stranded to the right. The change
    /// takes that room back as clear space after itself, which keeps the item
    /// one width and the change against the price at the same time.
    var menuBarSlack: CGFloat {
        guard let quote = menuBarQuote else { return 0 }
        let drawn = MenuBarPrice.width(of: MenuBarPrice.Label(
            coin: quote.coin,
            symbol: currency.symbol,
            amount: amount(quote.price),
            change: "",
            changeValue: quote.change
        ))
        return max(0, menuBarWidth - drawn)
    }

    /// The whole label as it will read in the menu bar, price and change
    /// together: what the settings page previews and a screen reader says.
    var menuBarReading: String {
        guard let quote = menuBarQuote else { return "" }
        return "\(quote.coin) \(currency.symbol)\(amount(quote.price)) \(formatArrowed(quote.change))"
            .trimmingCharacters(in: .whitespaces)
    }

    /// How the panel's footer names what the menu bar is doing.
    var menuBarSummary: String {
        if menuBarCoins.count > 1 { return "菜单栏：\(menuBarCoins.count) 个轮播" }
        let coin = menuBarQuote?.coin ?? menuBarCoins.first
        return "菜单栏：\(coin ?? "—")"
    }

    func isOnMenuBar(_ coin: String) -> Bool {
        menuBarCoins.contains(coin)
    }

    /// Adds a coin to the menu bar's turns, or takes it off. Taking the last
    /// one off is allowed: the menu bar falls back to the first price rather
    /// than refusing the click.
    func toggleMenuBar(_ coin: String) {
        menuBarCoins = MenuBarOrder.toggling(coin, panel: coins, menuBar: menuBarCoins)
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
        // Read the rate first, so that a panel in yuan shows numbers rather
        // than dashes from the first frame with prices in it.
        Task {
            await loadRate()
            refresh()
        }
        schedule()
        scheduleRotation()
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

    /// Turns the menu bar from one coin to the next. Only the label changes:
    /// the prices themselves are read on their own interval, so rotating
    /// costs no requests.
    private func scheduleRotation() {
        rotateTimer?.invalidate()
        rotationIndex = 0
        guard menuBarCoins.count > 1 else {
            rotateTimer = nil
            return
        }
        let every = max(1, rotateInterval)
        rotateTimer = Timer.scheduledTimer(withTimeInterval: every, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                guard !self.panelIsOnScreen else { return }
                self.rotationIndex += 1
            }
        }
    }

    func refresh() {
        guard !refreshing else { return }
        if let problem = proxyProblem {
            error = problem
            errorHint = nil
            return
        }

        refreshing = true
        let coins = coins
        let source = source
        let session = session

        Task {
            defer { refreshing = false }
            do {
                let quotes = try await PriceAPI.quotes(for: coins, source: source, session: session)
                self.quotes = quotes
                self.error = nil
                self.errorHint = nil
                self.checkAlerts(quotes)
            } catch {
                self.error = "\(source.label)：\(describe(error))"
                self.errorHint = self.hint(for: source)
            }
        }
    }

    /// What to try next, said in terms of the two things the user can change.
    private func hint(for source: MarketSource) -> String {
        switch settings.proxyMode {
        case .custom:
            return "检查代理是否在运行：\(settings.proxyAddress)"
        case .direct, .system:
            return source.normallyNeedsProxy
                ? "\(source.label) 通常要挂代理才能连上，可以在设置里开启。"
                : "在设置里换一个数据源试试。"
        }
    }

    /// Reads one coin through the current source and proxy, and reports what
    /// came back: the one way to tell a blocked source from a wrong address.
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
        let coin = coins.first ?? "BTC"
        let started = Date()

        Task {
            defer { testing = false }
            do {
                let quotes = try await PriceAPI.quotes(for: [coin], source: source, session: session)
                let ms = Int(Date().timeIntervalSince(started) * 1000)
                if let quote = quotes.first {
                    connectionTest = ConnectionResult(
                        ok: true,
                        text: "\(source.label) 正常 · \(ms)ms · \(coin) \(money(quote.price))"
                    )
                } else {
                    connectionTest = ConnectionResult(
                        ok: false,
                        text: "\(source.label) 有响应，但没有 \(coin) 的报价"
                    )
                }
            } catch {
                connectionTest = ConnectionResult(
                    ok: false,
                    text: "\(source.label) 失败：\(describe(error))"
                )
            }
        }
    }

    private func checkAlerts(_ quotes: [Quote]) {
        let alerts = engine.evaluate(quotes)
        guard !alerts.isEmpty else { return }
        // The engine owns the armed flags, so store what it decided.
        rules = engine.rules
        for alert in alerts {
            Notifier.send(
                title: alert.title,
                body: alert.body(currency: currency, rate: displayRate ?? 1)
            )
        }
    }

    // MARK: - Coins

    /// Adds a coin the exchange knows, and reports why it could not.
    func addCoin(_ raw: String) async -> String? {
        let coin = CoinValidation.normalize(raw)
        if let problem = CoinValidation.problem(coin: coin, existing: coins) {
            return problem
        }
        let known = await PriceAPI.exists(coin: coin, source: source, session: session)
        if let problem = CoinValidation.problem(coin: coin, knownToExchange: known) {
            return problem
        }
        coins.append(coin)
        return nil
    }

    func removeCoin(_ coin: String) {
        coins.removeAll { $0 == coin }
        rules.removeAll { $0.coin == coin }
        lines[coin] = nil
        linesReadAt[coin] = nil
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
        // A coin taken off the panel takes its menu bar turn with it.
        after.menuBarCoins = MenuBarOrder.settled(after.menuBarCoins, panel: after.coins)
        guard after != before else { return }

        let reread = after.coins != before.coins
        let reconnect = after.source != before.source
            || after.proxyMode != before.proxyMode
            || after.proxyAddress != before.proxyAddress
        let reschedule = after.interval != before.interval
        let rerotate = after.menuBarCoins != before.menuBarCoins
            || after.rotateInterval != before.rotateInterval
        let needRate = after.currency == .cny && rate == nil

        settings = after
        after.save()

        if reconnect {
            session = ProxySettings(mode: after.proxyMode, address: after.proxyAddress).session()
            // A day of candles from another exchange is another shape.
            lines.removeAll()
            linesReadAt.removeAll()
            connectionTest = nil
            // The panel is already open, so nothing will ask for the lines
            // again until it is reopened: ask now, on the new source.
            if panelIsOnScreen { loadLines(force: true) }
        }
        if reschedule { schedule() }
        if rerotate { scheduleRotation() }
        if needRate { Task { await loadRate() } }
        if reread || reconnect { refresh() }
    }
}
