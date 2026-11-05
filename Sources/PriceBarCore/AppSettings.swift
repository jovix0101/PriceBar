import Foundation

/// A currency the prices are shown in.
public enum Currency: String, Codable, CaseIterable, Sendable {
    case usd = "USD"
    case cny = "CNY"

    public var symbol: String {
        switch self {
        case .usd: "$"
        case .cny: "¥"
        }
    }
}

/// Which color means a rise.
///
/// Crypto markets the world over draw a rise green, a fall red; Chinese
/// markets, and the habit most readers here bring, do the opposite. The
/// setting is the whole of that difference — the arrow beside the number
/// says which way it went either way.
public enum ChangeColors: String, Codable, CaseIterable, Sendable {
    case greenUp = "greenUp"
    case redUp = "redUp"

    public var label: String {
        switch self {
        case .greenUp: "绿涨红跌"
        case .redUp: "红涨绿跌"
        }
    }

    /// Whether this change should be drawn green, or nil when it is too small
    /// to have a side at all.
    ///
    /// The panel's percentage and the menu bar's label both ask here, so that
    /// the two can never point opposite ways.
    public func isGreen(_ change: Double) -> Bool? {
        guard abs(change) >= 0.005 else { return nil }
        let up = change > 0
        switch self {
        case .greenUp: return up
        case .redUp: return !up
        }
    }
}

/// What colour the menu bar writes the price in.
///
/// The label is drawn as a template image, which takes the menu bar's own
/// tint and so follows light and dark by itself. But the menu bar is
/// translucent now: over a bright wallpaper the tint it picks can sit on a
/// light strip and be hard to read. These are the way out — draw the label
/// dark, or light, and stop following.
///
/// The fourth choice gives the colour back to the price's own movement: green
/// when it is up, red when it is down, the same way the panel's percentage is
/// drawn. A change too small to have a side falls back to the menu bar's own
/// tint, because there is nothing to colour.
public enum MenuBarTint: String, Codable, CaseIterable, Sendable {
    case automatic, dark, light, change

    public var label: String {
        switch self {
        case .automatic: "自动"
        case .dark: "深色"
        case .light: "浅色"
        case .change: "随涨跌"
        }
    }
}

/// Everything the app remembers between launches.
public struct AppSettings: Codable, Equatable, Sendable {
    public var coins: [String] = ["BTC", "ETH"]
    /// The coins the menu bar shows, side by side, in the order the panel
    /// lists them.
    public var menuBarCoins: [String] = ["BTC"]
    public var currency: Currency = .usd
    /// How often the prices are read, in seconds.
    public var interval: Double = 10
    /// Which color means a rise.
    public var changeColors: ChangeColors = .greenUp
    /// What colour the menu bar writes the price in.
    public var menuBarTint: MenuBarTint = .automatic
    /// Which exchange the prices come from.
    public var source: MarketSource = .binance
    /// How the app reaches that exchange.
    public var proxyMode: ProxyMode = .direct
    public var proxyAddress: String = ""
    public var rules: [Rule] = []

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case coins, menuBarCoins, currency, interval, changeColors
        case menuBarTint
        case source, proxyMode, proxyAddress, rules
        /// Written by versions that had one coin on the menu bar.
        case primary
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(coins, forKey: .coins)
        try container.encode(menuBarCoins, forKey: .menuBarCoins)
        try container.encode(currency, forKey: .currency)
        try container.encode(interval, forKey: .interval)
        try container.encode(changeColors, forKey: .changeColors)
        try container.encode(menuBarTint, forKey: .menuBarTint)
        try container.encode(source, forKey: .source)
        try container.encode(proxyMode, forKey: .proxyMode)
        try container.encode(proxyAddress, forKey: .proxyAddress)
        try container.encode(rules, forKey: .rules)
    }

    /// Reads the settings field by field, so that one field a later version
    /// wrote differently does not throw away the rest: the coins and the
    /// rules outlive a currency the app no longer knows.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings()

        coins = (try? container.decode([String].self, forKey: .coins)) ?? defaults.coins
        currency = (try? container.decode(Currency.self, forKey: .currency)) ?? defaults.currency
        interval = (try? container.decode(Double.self, forKey: .interval)) ?? defaults.interval
        changeColors = (try? container.decode(ChangeColors.self, forKey: .changeColors)) ?? defaults.changeColors
        menuBarTint = (try? container.decode(MenuBarTint.self, forKey: .menuBarTint)) ?? defaults.menuBarTint
        source = (try? container.decode(MarketSource.self, forKey: .source)) ?? defaults.source
        proxyMode = (try? container.decode(ProxyMode.self, forKey: .proxyMode)) ?? defaults.proxyMode
        proxyAddress = (try? container.decode(String.self, forKey: .proxyAddress)) ?? defaults.proxyAddress

        // The menu bar coins: an older file names one of them `primary`, and
        // a coin taken off the panel takes its menu bar place with it. An
        // older file also kept them in the order they were ticked, so they
        // are put in panel order here.
        let stored = try? container.decode([String].self, forKey: .menuBarCoins)
        let legacy = try? container.decode(String.self, forKey: .primary)
        // An empty list is a real answer ("show the first price"), so it is
        // kept as it is; only coins no longer on the panel are dropped.
        let wanted = stored ?? legacy.map { [$0] } ?? defaults.menuBarCoins
        menuBarCoins = CoinOrder.settled(wanted, panel: coins)
        // A rule the app cannot read goes; the others stay.
        if let decoded = try? container.decode([Lenient<Rule>].self, forKey: .rules) {
            rules = decoded.compactMap(\.value)
        } else {
            rules = []
        }
    }

    /// The settings stored in Application Support, or the defaults.
    public static func load() -> AppSettings {
        guard let data = try? Data(contentsOf: fileURL),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data)
        else { return AppSettings() }
        return settings
    }

    public func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? FileManager.default.createDirectory(
            at: Self.fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: Self.fileURL, options: .atomic)
    }

    /// The settings live beside the app's other data, in
    /// ~/Library/Application Support/PriceBar/settings.json.
    public static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("PriceBar/settings.json")
    }
}

/// Decodes a value, or nothing when it cannot: one unreadable element of an
/// array does not take the array with it.
struct Lenient<Wrapped: Decodable>: Decodable {
    let value: Wrapped?

    init(from decoder: Decoder) throws {
        value = try? Wrapped(from: decoder)
    }
}

/// The prices the app shows, and the rules it checks against them.
///
/// A rule fires once when its value crosses the threshold, and stays quiet
/// until the value returns to the other side, so a price resting on the
/// threshold notifies one time.
public struct AlertEngine {
    public struct Alert: Equatable, Sendable {
        public let rule: Rule
        public let quote: Quote
        public let value: Double

        /// The threshold is in US dollars whatever the panel shows, so the
        /// title names dollars: a rule set at 80000 fires at $80,000.
        public var title: String {
            let name = quote.coin
            switch rule.metric {
            case .price:
                return rule.above
                    ? "\(name) 突破 \(formatMoney(rule.threshold, currency: .usd))"
                    : "\(name) 跌破 \(formatMoney(rule.threshold, currency: .usd))"
            case .change:
                return rule.above
                    ? "\(name) 24h 涨幅超 \(formatPercent(rule.threshold))"
                    : "\(name) 24h 跌幅超 \(formatPercent(rule.threshold))"
            }
        }

        /// The current price in the currency the panel shows, so that the
        /// notification reads like the panel it describes.
        public func body(currency: Currency = .usd, rate: Double = 1) -> String {
            let price = formatMoney(quote.price * rate, currency: currency)
            return "现价 \(price)，24h \(formatSigned(quote.change))"
        }
    }

    /// The rules, armed or not.
    public private(set) var rules: [Rule]

    public init(rules: [Rule] = []) {
        self.rules = rules
    }

    /// Checks every quote against every rule, arming the rules that came
    /// back to the other side, and returns the ones that fired.
    public mutating func evaluate(_ quotes: [Quote]) -> [Alert] {
        var alerts: [Alert] = []
        for index in rules.indices {
            let rule = rules[index]
            guard let quote = quotes.first(where: { $0.coin == rule.coin }),
                  let value = rule.value(of: quote)
            else { continue }

            if rule.armed {
                let fired = rule.above ? value >= rule.threshold : value <= rule.threshold
                if fired {
                    rules[index].armed = false
                    alerts.append(Alert(rule: rule, quote: quote, value: value))
                }
            } else {
                // Rearm once the value is clear of the threshold by the
                // hysteresis band, so that a value hovering on it does not
                // notify again and again.
                let back = rule.above
                    ? value < rule.threshold - rule.hysteresis
                    : value > rule.threshold + rule.hysteresis
                if back {
                    rules[index].armed = true
                }
            }
        }
        return alerts
    }
}

/// A price with the digits people read: none above a thousand, two below,
/// four for the small ones — and thousands split up, because "77150" has to
/// be counted to be read.
public func formatPrice(_ price: Double) -> String {
    if price >= 1000 { return grouped(price, decimals: 0) }
    if price >= 1 { return grouped(price, decimals: 2) }
    return grouped(price, decimals: 4)
}

/// A number with a comma every three digits: "77,150", "1,234,568".
///
/// Written out rather than left to `NumberFormatter`, whose separators come
/// from the reader's region: the price of a coin reads the same everywhere.
func grouped(_ value: Double, decimals: Int) -> String {
    let text = String(format: "%.\(decimals)f", abs(value))
    let whole = text.split(separator: ".", maxSplits: 1)[0]
    let fraction = text.contains(".") ? "." + text.split(separator: ".", maxSplits: 1)[1] : ""

    var digits = ""
    for (offset, character) in whole.reversed().enumerated() {
        if offset > 0 && offset % 3 == 0 { digits.append(",") }
        digits.append(character)
    }
    return (value < 0 ? "-" : "") + String(digits.reversed()) + fraction
}

/// A price with its currency's symbol.
public func formatMoney(_ price: Double, currency: Currency = .usd) -> String {
    currency.symbol + formatPrice(price)
}

/// A 24h change with its sign: "+2.41%".
public func formatSigned(_ change: Double) -> String {
    String(format: "%+.2f%%", change)
}

/// A 24h change as the menu bar writes it: an arrow for the direction, then
/// the number: "▲2.02%", "▼0.31%".
///
/// The arrow carries what colour carries in the panel. A menu bar item drawn
/// as a template image takes one tint and cannot be green or red, and an arrow
/// reads at a glance for someone who cannot tell those two colours apart.
///
/// A change that would print as "0.00%" gets no arrow: pointing at nothing is
/// worse than saying nothing. It still prints the number, though. An empty
/// change would leave the menu bar item holding room for a value that never
/// arrives, which reads as the number being missing rather than as flat.
public func formatArrowed(_ change: Double) -> String {
    guard abs(change) >= 0.005 else { return "0%" }
    return (change > 0 ? "▲" : "▼") + formatPercent(change)
}

/// A threshold as a percentage, without its sign: "5%", "0.5%".
///
/// The decimals a user typed are kept — a rule at 0.5% that reads "0%" is a
/// different rule from the one they set — but a whole number keeps its short
/// form, so 5 does not become "5.00%".
public func formatPercent(_ value: Double) -> String {
    var text = String(format: "%.2f", abs(value))
    while text.hasSuffix("0") { text.removeLast() }
    if text.hasSuffix(".") { text.removeLast() }
    return text + "%"
}
