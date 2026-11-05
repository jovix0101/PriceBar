import Testing
import Foundation
@testable import PriceBarCore

@Suite("价格与涨跌幅的格式")
struct FormatTests {
    @Test("小数位数跟着量级走")
    func priceDigitsFollowMagnitude() {
        #expect(formatPrice(77743.99) == "77,744")
        #expect(formatPrice(1000) == "1,000")
        #expect(formatPrice(999.5) == "999.50")
        #expect(formatPrice(1) == "1.00")
        #expect(formatPrice(0.4213) == "0.4213")
        #expect(formatPrice(1234567) == "1,234,567")
    }

    @Test("价格带上货币符号")
    func moneyUsesCurrencySymbol() {
        #expect(formatMoney(77743.99) == "$77,744")
        #expect(formatMoney(77743.99, currency: .cny) == "¥77,744")
    }

    @Test("涨跌幅带正负号")
    func signedChange() {
        #expect(formatSigned(2.41) == "+2.41%")
        #expect(formatSigned(-0.308) == "-0.31%")
        #expect(formatSigned(0) == "+0.00%")
    }

    @Test("A klines response is read as its closing prices")
    func klinesCloses() throws {
        // Two candles, shaped as the exchange sends them: an open time, then
        // strings of prices.
        let json = """
        [[1793646000000,"77022.01","77100.00","76705.00","77096.29"],
         [1793649600000,"77096.29","77200.00","76900.00","77150.50"]]
        """
        let closes = try PriceAPI.closes(from: Data(json.utf8), source: .binance)
        #expect(closes == [77096.29, 77150.50])
        // A candle missing its close is left out rather than failing the lot.
        #expect(try PriceAPI.closes(from: Data("[[1,2,3]]".utf8), source: .binance).isEmpty)
    }

    @Test("菜单栏的涨跌幅用箭头表明方向")
    func arrowedChange() {
        #expect(formatArrowed(2.02) == "▲2.02%")
        #expect(formatArrowed(-0.31) == "▼0.31%")
        // Rounds to 0.00%: no arrow rather than one pointing at nothing, but
        // still a number. A blank there would read as the value being missing.
        #expect(formatArrowed(0) == "0%")
        #expect(formatArrowed(0.004) == "0%")
        #expect(formatArrowed(-0.004) == "0%")
        // Whole numbers keep their short form.
        #expect(formatArrowed(5) == "▲5%")
    }

    @Test("A percentage threshold keeps the decimals it was given")
    func percentKeepsDecimals() {
        #expect(formatPercent(5) == "5%")
        #expect(formatPercent(0.5) == "0.5%")
        #expect(formatPercent(2.25) == "2.25%")
    }
}

@Suite("提醒规则")
struct AlertEngineTests {
    private func quote(_ coin: String, _ price: Double, change: Double = 0) -> Quote {
        Quote(coin: coin, price: price, change: change)
    }

    @Test("越过阈值只通知一次")
    func firesOnceWhileTheValueStaysPastTheThreshold() {
        var engine = AlertEngine(rules: [
            Rule(coin: "BTC", metric: .price, above: true, threshold: 80000)
        ])

        // Below the threshold: quiet.
        #expect(engine.evaluate([quote("BTC", 79000)]).isEmpty)

        // Crossing it: one alert.
        let fired = engine.evaluate([quote("BTC", 81000)])
        #expect(fired.count == 1)
        #expect(fired.first?.rule.threshold == 80000)

        // Still past it: quiet, the rule is not armed.
        #expect(engine.evaluate([quote("BTC", 81500)]).isEmpty)
        #expect(engine.evaluate([quote("BTC", 90000)]).isEmpty)
    }

    @Test("滞回带压住贴线的抖动")
    func hysteresisKeepsAValueOnTheThresholdQuiet() {
        var engine = AlertEngine(rules: [
            Rule(coin: "BTC", metric: .price, above: true, threshold: 80000)
        ])
        _ = engine.evaluate([quote("BTC", 81000)])

        // Back below the threshold but inside the 0.3% band: still quiet.
        #expect(engine.evaluate([quote("BTC", 79800)]).isEmpty)

        // Clear of the band: the rule arms again, and fires on the next
        // crossing.
        #expect(engine.evaluate([quote("BTC", 79000)]).isEmpty)
        #expect(engine.evaluate([quote("BTC", 80100)]).count == 1)
    }

    @Test("低于阈值的方向")
    func belowRulesFireDownward() {
        var engine = AlertEngine(rules: [
            Rule(coin: "BTC", metric: .price, above: false, threshold: 70000)
        ])
        #expect(engine.evaluate([quote("BTC", 72000)]).isEmpty)
        #expect(engine.evaluate([quote("BTC", 69000)]).count == 1)
    }

    @Test("涨跌幅规则看百分比")
    func changeRulesWatchThePercent() {
        var engine = AlertEngine(rules: [
            Rule(coin: "ETH", metric: .change, above: false, threshold: -5)
        ])
        #expect(engine.evaluate([quote("ETH", 2300, change: -2)]).isEmpty)
        let fired = engine.evaluate([quote("ETH", 2300, change: -6.2)])
        #expect(fired.count == 1)
        #expect(fired.first?.title == "ETH 24h 跌幅超 5%")
    }

    @Test("通知正文跟随面板的货币")
    func alertBodyFollowsTheCurrency() {
        let alert = AlertEngine.Alert(
            rule: Rule(coin: "BTC", metric: .price, above: true, threshold: 90000),
            quote: quote("BTC", 90500, change: 2.41),
            value: 90500
        )
        #expect(alert.body() == "现价 $90,500，24h +2.41%")
        #expect(alert.body(currency: .cny, rate: 6.67) == "现价 ¥603,635，24h +2.41%")
        // The title names dollars whatever the panel shows: a threshold is
        // always a dollar amount.
        #expect(alert.title == "BTC 突破 $90,000")
    }

    @Test("通知标题说明方向")
    func alertTitlesNameTheDirection() {
        let above = AlertEngine.Alert(
            rule: Rule(coin: "BTC", metric: .price, above: true, threshold: 90000),
            quote: quote("BTC", 90500),
            value: 90500
        )
        #expect(above.title == "BTC 突破 $90,000")

        let below = AlertEngine.Alert(
            rule: Rule(coin: "BTC", metric: .price, above: false, threshold: 70000),
            quote: quote("BTC", 69500),
            value: 69500
        )
        #expect(below.title == "BTC 跌破 $70,000")
    }

    @Test("规则指向已删除的币种时什么都不做")
    func ruleForACoinThatIsGoneDoesNothing() {
        var engine = AlertEngine(rules: [
            Rule(coin: "DOGE", metric: .price, above: true, threshold: 1)
        ])
        #expect(engine.evaluate([quote("BTC", 80000)]).isEmpty)
    }
}

@Suite("设置的读写")
struct SettingsTests {
    @Test("默认值")
    func defaults() {
        let settings = AppSettings()
        #expect(settings.coins == ["BTC", "ETH"])
        #expect(settings.menuBarCoins == ["BTC"])
        #expect(settings.source == .binance)
        #expect(settings.proxyMode == .direct)
        #expect(settings.currency == .usd)
        #expect(settings.interval == 10)
        #expect(settings.rules.isEmpty)
    }

    @Test("面板行数默认八行，写坏的值回落")
    func panelRowLimit() throws {
        #expect(AppSettings().panelRows == 8)
        // A limit of zero would show no prices at all; a limit of a thousand
        // would put the footer below the screen again.
        for bad in [0, -5, 2, 999] {
            let json = #"{"panelRows":\#(bad)}"#
            let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
            #expect(settings.panelRows == 8)
        }
        var chosen = AppSettings()
        chosen.panelRows = 12
        let back = try JSONDecoder().decode(
            AppSettings.self, from: JSONEncoder().encode(chosen))
        #expect(back.panelRows == 12)
    }

    @Test("点击打开合约页默认开，关掉后能存住，旧文件当作开")
    func openContractOnClick() throws {
        #expect(AppSettings().openContractOnClick)
        var off = AppSettings()
        off.openContractOnClick = false
        let back = try JSONDecoder().decode(
            AppSettings.self, from: JSONEncoder().encode(off))
        #expect(!back.openContractOnClick)
        let old = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"coins":["BTC"]}"#.utf8))
        #expect(old.openContractOnClick)
    }

    @Test("JSON 往返")
    func roundTripThroughJSON() throws {
        var settings = AppSettings()
        settings.coins = ["BTC", "SOL"]
        settings.menuBarCoins = ["SOL"]
        settings.source = .okx
        settings.proxyMode = .custom
        settings.proxyAddress = "http://127.0.0.1:1080"
        settings.currency = .cny
        settings.rules = [Rule(coin: "SOL", metric: .change, above: false, threshold: -8)]

        let data = try JSONEncoder().encode(settings)
        let back = try JSONDecoder().decode(AppSettings.self, from: data)
        #expect(back == settings)
    }
}

@Suite("真实行情", .enabled(if: ProcessInfo.processInfo.environment["NETWORK_TESTS"] == "1"))
struct NetworkTests {
    @Test("取到 BTC 和 ETH 的价格")
    func fetchesQuotes() async throws {
        let quotes = try await PriceAPI.quotes(for: ["BTC", "ETH"])
        #expect(quotes.count == 2)
        #expect(quotes.first?.coin == "BTC")
        #expect(quotes.last?.coin == "ETH")
        for quote in quotes {
            #expect(quote.price > 0)
        }
    }

    @Test("四家都能报出同一个币的价格", arguments: MarketSource.allCases)
    func everySourceQuotes(source: MarketSource) async throws {
        // Binance and Gate answer this network directly; OKX and Bybit only
        // through the proxy the user runs.
        let proxy = source.normallyNeedsProxy
            ? ProxySettings(mode: .custom, address: "http://127.0.0.1:1080")
            : ProxySettings(mode: .direct)
        let quotes = try await PriceAPI.quotes(for: ["BTC"], source: source, session: proxy.session())
        let quote = try #require(quotes.first)
        #expect(quote.price > 10000)
        #expect(abs(quote.change) < 30)
    }

    @Test("四家都能报出黄金和苹果的永续合约", arguments: MarketSource.allCases)
    func everySourceQuotesContracts(source: MarketSource) async throws {
        let proxy = source.normallyNeedsProxy(for: .perpetual)
            ? ProxySettings(mode: .custom, address: "http://127.0.0.1:1080")
            : ProxySettings(mode: .direct)
        let session = proxy.session()
        let reading = await PriceAPI.read(["BTC", "XAU.P", "AAPL.P", "NOPEZZ.P"], source: source, session: session)
        #expect(reading.quotes.map(\.coin) == ["BTC", "XAU.P", "AAPL.P"])
        let gold = try #require(reading.quotes.first { $0.coin == "XAU.P" })
        #expect(gold.price > 1000)
        #expect(reading.missing["NOPEZZ.P"] == .notListed)
        let line = try await PriceAPI.closes(coin: "XAU.P", source: source, session: session)
        #expect(line.count > 12)
    }

    @Test("Binance 一次问多个币时，有一个不认识也不连累其他")
    func binanceBatchSurvivesAnUnknownCode() async {
        let reading = await PriceAPI.read(["BTC", "ETH", "NOPEZZ"])
        #expect(reading.quotes.map(\.coin) == ["BTC", "ETH"])
        #expect(reading.missing["NOPEZZ"] == .notListed)
    }

    @Test("汇率是正数")
    func fetchesRate() async throws {
        let rate = try await FXAPI.usdToCNY()
        #expect(rate > 1)
    }
}

@Suite("设置文件的兼容性")
struct SettingsFileTests {
    @Test("能读回写出去的规则")
    func decodesARule() throws {
        let json = """
        {"coins":["BTC"],"primary":"BTC","currency":"USD","interval":10,
         "rules":[{"id":"2F1A0C3E-1111-4A2B-9C3D-000000000001","coin":"BTC",
                   "metric":"price","above":true,"threshold":70000,"armed":true}]}
        """
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(settings.rules.count == 1)
        #expect(settings.rules[0].coin == "BTC")
        #expect(settings.rules[0].metric == .price)
    }

    @Test("旧设置文件没有颜色字段时按绿涨红跌")
    func changeColorsDefaults() throws {
        let json = #"{"coins":["BTC"],"primary":"BTC","currency":"USD","interval":10,"rules":[]}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(settings.changeColors == .greenUp)
        // And the choice survives a round trip.
        var chosen = settings
        chosen.changeColors = .redUp
        let again = try JSONDecoder().decode(
            AppSettings.self, from: JSONEncoder().encode(chosen))
        #expect(again.changeColors == .redUp)
    }

    @Test("旧设置文件没有文字颜色字段时按自动")
    func menuBarTintDefaults() throws {
        let json = #"{"coins":["BTC"],"primary":"BTC","currency":"USD","interval":10,"rules":[]}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(settings.menuBarTint == .automatic)
        // And a chosen colour survives a round trip.
        var chosen = settings
        chosen.menuBarTint = .light
        let again = try JSONDecoder().decode(
            AppSettings.self, from: JSONEncoder().encode(chosen))
        #expect(again.menuBarTint == .light)
        // A colour it does not know falls back rather than losing the file.
        let odd = #"{"coins":["BTC"],"currency":"USD","menuBarTint":"purple"}"#
        let read = try JSONDecoder().decode(AppSettings.self, from: Data(odd.utf8))
        #expect(read.menuBarTint == .automatic)
        #expect(read.coins == ["BTC"])
        // The colour that follows the change is a value of its own, and
        // survives the same way.
        let following = try JSONDecoder().decode(
            AppSettings.self, from: Data(#"{"menuBarTint":"change"}"#.utf8))
        #expect(following.menuBarTint == .change)
    }

    @Test("随涨跌：谁涨谁跌，面板和菜单栏不会指反")
    func changeColoursAgree() {
        // Green up: up is green, down is red.
        #expect(ChangeColors.greenUp.isGreen(2.02) == true)
        #expect(ChangeColors.greenUp.isGreen(-0.31) == false)
        // Red up: the same movement, the other colour.
        #expect(ChangeColors.redUp.isGreen(2.02) == false)
        #expect(ChangeColors.redUp.isGreen(-0.31) == true)
        // Something too small to print an arrow has no side to colour, so
        // both the arrow and the colour go quiet together.
        #expect(ChangeColors.greenUp.isGreen(0) == nil)
        #expect(ChangeColors.greenUp.isGreen(0.004) == nil)
        #expect(ChangeColors.redUp.isGreen(-0.004) == nil)
        #expect(ChangeColors.greenUp.isGreen(0.005) == true)
    }

    @Test("一个读不懂的字段不会带走其余设置")
    func anUnreadableFieldKeepsTheRest() throws {
        // "usd" is not a Currency the app knows; the coins and the rule
        // still arrive.
        let json = """
        {"coins":["BTC","SOL"],"primary":"SOL","currency":"usd","interval":15,
         "rules":[{"id":"2F1A0C3E-1111-4A2B-9C3D-000000000001","coin":"BTC",
                   "metric":"price","above":true,"threshold":70000,"armed":true}]}
        """
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(settings.coins == ["BTC", "SOL"])
        #expect(settings.menuBarCoins == ["SOL"])
        #expect(settings.currency == .usd)   // the default
        #expect(settings.interval == 15)
        #expect(settings.rules.count == 1)
    }

    @Test("读不懂的规则被跳过，其余保留")
    func unreadableRulesAreSkipped() throws {
        let json = """
        {"coins":["BTC"],"rules":[
          {"id":"2F1A0C3E-1111-4A2B-9C3D-000000000001","coin":"BTC",
           "metric":"price","above":true,"threshold":70000,"armed":true},
          {"coin":"ETH","metric":"nonsense","above":true,"threshold":1}
        ]}
        """
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(settings.rules.count == 1)
        #expect(settings.rules[0].coin == "BTC")
    }
}

@Suite("添加币种的校验")
struct CoinValidationTests {
    @Test("代号不区分大小写，去掉空格")
    func normalizesTheCode() {
        #expect(CoinValidation.normalize(" sol ") == "SOL")
        #expect(CoinValidation.normalize("btc") == "BTC")
        #expect(CoinValidation.normalize("   ") == "")
    }

    @Test("空输入与现货、合约都加过时不动网络")
    func rejectsBeforeAskingTheExchange() {
        #expect(CoinValidation.problem(coin: "", existing: ["BTC"]) == "请输入代号")
        #expect(CoinValidation.problem(coin: "BTC", existing: ["BTC", "BTC.P"]) == "已经添加过 BTC")
        // Spot alone is not everything: the contract may still be added.
        #expect(CoinValidation.problem(coin: "BTC", existing: ["BTC", "ETH"]) == nil)
        #expect(CoinValidation.problem(coin: "SOL", existing: ["BTC"]) == nil)
    }

    private func reading(_ found: [String], missing: [String: PriceAPI.Absence] = [:]) -> PriceAPI.Reading {
        PriceAPI.Reading(quotes: found.map { Quote(coin: $0, price: 1, change: 0) }, missing: missing)
    }

    @Test("现货和合约都有时让用户选，现货在前")
    func offersBothMarkets() {
        let decision = CoinValidation.decide(
            code: "BTC", existing: [], reading: reading(["BTC", "BTC.P"]), source: .binance)
        guard case let .choose(choices) = decision else {
            Issue.record("应该让用户选：\(decision)"); return
        }
        #expect(choices.map(\.instrument.id) == ["BTC", "BTC.P"])
        #expect(choices.allSatisfy { $0.state == .available })
    }

    @Test("只有合约的直接加，比如黄金和美股")
    func addsAContractOnlyCode() {
        let decision = CoinValidation.decide(
            code: "XAU", existing: [],
            reading: reading(["XAU.P"], missing: ["XAU": .notListed]), source: .gate)
        #expect(decision == .add(Instrument(code: "XAU", market: .perpetual)))
    }

    @Test("现货加过了，合约仍可加，现货显示已添加")
    func showsWhatIsAlreadyAdded() {
        let decision = CoinValidation.decide(
            code: "BTC", existing: ["BTC"], reading: reading(["BTC", "BTC.P"]), source: .okx)
        guard case let .choose(choices) = decision else {
            Issue.record("应该让用户选：\(decision)"); return
        }
        #expect(choices.map(\.state) == [.added, .available])
    }

    @Test("合约连不上时照样能加现货，但要说明")
    func greysOutAnUnreachableMarket() {
        let decision = CoinValidation.decide(
            code: "BTC", existing: [],
            reading: reading(["BTC"], missing: ["BTC.P": .unreachable("HTTP 451")]), source: .binance)
        guard case let .choose(choices) = decision else {
            Issue.record("应该让用户选：\(decision)"); return
        }
        #expect(choices.map(\.state) == [.available, .unreachable("HTTP 451")])
    }

    @Test("两边都没有，说清楚是哪家没有")
    func explainsAMissingCode() {
        let decision = CoinValidation.decide(
            code: "NOPE", existing: [],
            reading: reading([], missing: ["NOPE": .notListed, "NOPE.P": .notListed]), source: .bybit)
        #expect(decision == .problem("Bybit 没有 NOPE 的现货或永续合约"))

        let blocked = CoinValidation.decide(
            code: "XAU", existing: [],
            reading: reading([], missing: ["XAU": .notListed, "XAU.P": .unreachable("请求超时")]),
            source: .binance)
        #expect(blocked == .problem("连不上 Binance：请求超时"))
    }
}

@Suite("现货与永续合约")
struct InstrumentTests {
    @Test("代号后面的 .P 是永续合约，没有就是现货")
    func readsTheStoredForm() {
        #expect(Instrument(id: "BTC") == Instrument(code: "BTC", market: .spot))
        #expect(Instrument(id: "xau.p") == Instrument(code: "XAU", market: .perpetual))
        #expect(Instrument(code: "aapl", market: .perpetual).id == "AAPL.P")
        #expect(Instrument(id: "XAU.P").name == "XAU 合约")
        #expect(Instrument(id: "BTC").name == "BTC")
    }

    @Test("旧设置里的币种都按现货读")
    func oldSettingsAreSpot() throws {
        let settings = try JSONDecoder().decode(
            AppSettings.self, from: Data(#"{"coins":["BTC","ETH"]}"#.utf8))
        #expect(settings.coins.map { Instrument(id: $0).market } == [.spot, .spot])
    }

    @Test("合约在每家的写法")
    func perpetualSymbols() {
        let xau = Instrument(code: "XAU", market: .perpetual)
        #expect(MarketSource.binance.symbol(for: xau) == "XAUUSDT")
        #expect(MarketSource.gate.symbol(for: xau) == "XAU_USDT")
        #expect(MarketSource.okx.symbol(for: xau) == "XAU-USDT-SWAP")
        #expect(MarketSource.bybit.symbol(for: xau) == "XAUUSDT")
        #expect(MarketSource.okx.symbol(for: Instrument(code: "BTC", market: .spot)) == "BTC-USDT")
    }

    @Test("币安合约要挂代理，现货不用")
    func binanceContractsWantAProxy() {
        #expect(!MarketSource.binance.normallyNeedsProxy(for: .spot))
        #expect(MarketSource.binance.normallyNeedsProxy(for: .perpetual))
        #expect(!MarketSource.gate.normallyNeedsProxy(for: .perpetual))
        #expect(MarketSource.okx.normallyNeedsProxy(for: .spot))
    }

    @Test("Gate 合约的报价字段叫 contract")
    func readsAGateContractTicker() {
        let json = """
        [{"contract":"XAU_USDT","last":"4128.9","low_24h":"4037.31","high_24h":"4151.77",
          "change_percentage":"1.95","funding_rate":"0.0001"}]
        """
        let quote = PriceAPI.quote(from: Data(json.utf8), source: .gate, coin: "XAU.P")
        #expect(quote?.coin == "XAU.P")
        #expect(quote?.price == 4128.9)
        #expect(quote?.change == 1.95)
    }

    @Test("Gate 合约的 K 线是对象，收盘价在 c")
    func readsGateContractCandles() throws {
        let json = """
        [{"o":"4116.9","v":136468286,"t":1793890800,"c":"4089.57","l":"4081.9","h":"4126.24"},
         {"o":"4089.76","v":20689180,"t":1793894400,"c":"4090.77","l":"4089.52","h":"4097.73"}]
        """
        #expect(try PriceAPI.closes(from: Data(json.utf8), source: .gate, market: .perpetual)
                == [4089.57, 4090.77])
    }

    @Test("Binance 合约与现货同名，报价归到 .P 下")
    func readsABinanceContractTicker() throws {
        let one = #"{"symbol":"XAUUSDT","lastPrice":"4091.80","priceChangePercent":"0.95"}"#
        let quotes = try PriceAPI.binanceQuotes(
            from: Data(one.utf8), instruments: [Instrument(code: "XAU", market: .perpetual)])
        #expect(quotes.map(\.coin) == ["XAU.P"])
    }
}

@Suite("规则的文字")
struct RuleTextTests {
    @Test("价格阈值写成美元，与面板货币无关")
    func priceThresholdReadsInDollars() {
        let rule = Rule(coin: "BTC", metric: .price, above: true, threshold: 80000)
        #expect(rule.thresholdText == "$80,000")
        #expect(rule.metric.unit == "USD")
    }

    @Test("涨跌幅阈值写成百分比，不带符号")
    func changeThresholdReadsAsPercent() {
        let rule = Rule(coin: "BTC", metric: .change, above: false, threshold: -5)
        #expect(rule.thresholdText == "5%")
        #expect(rule.metric.unit == "%")
    }
}

@Suite("四家交易所的解析")
struct SourceParsingTests {
    @Test("每家都能给出这个币的合约行情页")
    func contractPages() {
        #expect(MarketSource.binance.contractPage(for: "BTC")?.absoluteString
            == "https://www.binance.com/zh-CN/futures/BTCUSDT")
        #expect(MarketSource.gate.contractPage(for: "eth")?.absoluteString
            == "https://www.gate.io/zh/futures/USDT/ETH_USDT")
        // OKX 的路径是小写交易对再加一个 -swap，写错一个字母就是 404。
        #expect(MarketSource.okx.contractPage(for: "Sol")?.absoluteString
            == "https://www.okx.com/zh-hans/trade-swap/sol-usdt-swap")
        #expect(MarketSource.bybit.contractPage(for: "BTC")?.absoluteString
            == "https://www.bybit.com/trade/usdt/BTCUSDT")
    }


    @Test("Gate 的字段名与交易对写法")
    func readsAGateTicker() throws {
        let json = """
        [{"currency_pair":"BTC_USDT","last":"77148.6","lowest_ask":"77148.7",
          "highest_bid":"77148.5","change_percentage":"-0.32","base_volume":"1200",
          "quote_volume":"92000000","high_24h":"78300","low_24h":"76200"}]
        """
        let quote = PriceAPI.quote(from: Data(json.utf8), source: .gate, coin: "BTC")
        #expect(quote?.coin == "BTC")
        #expect(quote?.price == 77148.6)
        #expect(quote?.change == -0.32)
    }

    @Test("OKX 不报涨跌，要自己从 24 小时前的开盘价算")
    func worksOutAnOKXChange() throws {
        // 77151.1 against an open of 76700 is a rise of 0.588%…
        let json = """
        {"code":"0","msg":"","data":[{"instId":"BTC-USDT","last":"77151.1",
          "open24h":"76700","high24h":"77900","low24h":"76000"}]}
        """
        let quote = PriceAPI.quote(from: Data(json.utf8), source: .okx, coin: "BTC")
        #expect(quote?.price == 77151.1)
        let change = try #require(quote?.change)
        #expect(abs(change - 0.5881) < 0.001)

        // An instrument OKX does not list comes back empty, not as a zero price.
        let missing = #"{"code":"51001","msg":"Instrument ID doesn't exist.","data":[]}"#
        #expect(PriceAPI.quote(from: Data(missing.utf8), source: .okx, coin: "NOPE") == nil)
    }

    @Test("Bybit 的涨跌是小数，要乘一百")
    func scalesABybitChange() throws {
        let json = """
        {"retCode":0,"retMsg":"OK","result":{"category":"spot","list":[
          {"symbol":"BTCUSDT","lastPrice":"77142.4","price24hPcnt":"-0.0034"}]}}
        """
        let quote = PriceAPI.quote(from: Data(json.utf8), source: .bybit, coin: "BTC")
        #expect(quote?.price == 77142.4)
        let change = try #require(quote?.change)
        #expect(abs(change - (-0.34)) < 0.0001)
    }

    @Test("Binance 一次问多个币，也能问一个")
    func readsBinanceTickers() throws {
        let list = """
        [{"symbol":"BTCUSDT","lastPrice":"77150.69","priceChangePercent":"0.96"},
         {"symbol":"ETHUSDT","lastPrice":"2293.4","priceChangePercent":"2.04"}]
        """
        let quotes = try PriceAPI.binanceQuotes(from: Data(list.utf8), coins: ["ETH", "BTC"])
        // The order is the one asked for, not the one answered in.
        #expect(quotes.map(\.coin) == ["ETH", "BTC"])
        #expect(quotes.first?.price == 2293.4)

        let one = #"{"symbol":"BTCUSDT","lastPrice":"77150.69","priceChangePercent":"0.96"}"#
        let single = try PriceAPI.binanceQuotes(from: Data(one.utf8), coins: ["BTC"])
        #expect(single.count == 1)
    }

    @Test("每家的收盘价在不同的位置，方向也不同")
    func readsEachExchangesCandles() throws {
        // Binance: the close is the fifth field, oldest first.
        let binance = """
        [[1793646000000,"77022.01","77100.00","76705.00","77096.29"],
         [1793649600000,"77096.29","77200.00","76900.00","77150.50"]]
        """
        #expect(try PriceAPI.closes(from: Data(binance.utf8), source: .binance)
                == [77096.29, 77150.50])

        // Gate: time, quote volume, close — third field.
        let gate = """
        [["1793646000","26029909.01","77096.29","77100.00","76705.00","77022.01"],
         ["1793649600","26029909.01","77150.50","77200.00","76900.00","77096.29"]]
        """
        #expect(try PriceAPI.closes(from: Data(gate.utf8), source: .gate)
                == [77096.29, 77150.50])

        // OKX: newest first, wrapped in an object.
        let okx = """
        {"code":"0","data":[["1793649600000","77096.29","77200.00","76900.00","77150.50"],
                            ["1793646000000","77022.01","77100.00","76705.00","77096.29"]]}
        """
        #expect(try PriceAPI.closes(from: Data(okx.utf8), source: .okx)
                == [77096.29, 77150.50])

        // Bybit: newest first, inside result.list.
        let bybit = """
        {"retCode":0,"result":{"list":[["1793649600000","77096.29","77200.00","76900.00","77150.50"],
                                       ["1793646000000","77022.01","77100.00","76705.00","77096.29"]]}}
        """
        #expect(try PriceAPI.closes(from: Data(bybit.utf8), source: .bybit)
                == [77096.29, 77150.50])
    }

    @Test("交易对的写法")
    func pairSpellings() {
        #expect(MarketSource.binance.pair(for: "btc") == "BTCUSDT")
        #expect(MarketSource.gate.pair(for: "btc") == "BTC_USDT")
        #expect(MarketSource.okx.pair(for: "btc") == "BTC-USDT")
        #expect(MarketSource.bybit.pair(for: "btc") == "BTCUSDT")
    }
}

@Suite("代理地址")
struct ProxySettingsTests {
    @Test("没写协议时按 HTTP 处理")
    func assumesHTTP() {
        let settings = ProxySettings(mode: .custom, address: "127.0.0.1:1080")
        #expect(settings.endpoint?.host == "127.0.0.1")
        #expect(settings.endpoint?.port == 1080)
        #expect(settings.endpoint?.isSocks == false)
        #expect(settings.problem == nil)
    }

    @Test("socks5 与 http 分开")
    func readsTheScheme() {
        #expect(ProxySettings(mode: .custom, address: "socks5://127.0.0.1:7890")
            .endpoint?.isSocks == true)
        #expect(ProxySettings(mode: .custom, address: "http://127.0.0.1:1080")
            .endpoint?.isSocks == false)
    }

    @Test("写错了就说清楚怎么写")
    func explainsABadAddress() {
        #expect(ProxySettings(mode: .custom, address: "").problem == "请填代理地址，例如 http://127.0.0.1:1080")
        #expect(ProxySettings(mode: .custom, address: "127.0.0.1").problem != nil)
        #expect(ProxySettings(mode: .custom, address: "ftp://127.0.0.1:1080").problem != nil)
        // The other two modes need no address at all.
        #expect(ProxySettings(mode: .direct, address: "").problem == nil)
        #expect(ProxySettings(mode: .system, address: "").problem == nil)
    }

    @Test("直连不查系统代理")
    func directGoesAroundTheSystem() {
        // An empty proxy dictionary means "ask the system", which is the
        // opposite of what 直连 says.
        let configuration = ProxySettings(mode: .direct, address: "").configuration()
        let proxy = try? #require(configuration.connectionProxyDictionary as? [String: Int])
        #expect(proxy?["HTTPEnable"] == 0)
        #expect(proxy?["HTTPSEnable"] == 0)
    }
}

@Suite("菜单栏的币种顺序")
struct CoinOrderTests {
    @Test("勾选时按面板顺序，不是按点击顺序")
    func addingKeepsPanelOrder() {
        #expect(CoinOrder.toggling("ETH", panel: ["BTC", "ETH", "SOL"], menuBar: ["SOL"])
                == ["ETH", "SOL"])
        #expect(CoinOrder.toggling("ETH", panel: ["BTC", "ETH", "SOL"], menuBar: [])
                == ["ETH"])
    }

    @Test("再点一次就取消")
    func togglingTwiceRemoves() {
        #expect(CoinOrder.toggling("BTC", panel: ["BTC", "ETH"], menuBar: ["BTC", "ETH"])
                == ["ETH"])
    }

    @Test("删掉币种时，菜单栏名单跟着收拾，并跟上面板的新顺序")
    func settledFollowsThePanel() {
        #expect(CoinOrder.settled(["BTC", "SOL"], panel: ["BTC", "ETH"]) == ["BTC"])
        // 一个都不剩就是空：菜单栏回落到面板第一个，但名单如实是空的。
        #expect(CoinOrder.settled(["SOL"], panel: ["BTC", "ETH"]) == [])
        // 面板换了顺序，勾选的那几个也跟着换。
        #expect(CoinOrder.settled(["BTC", "ETH"], panel: ["ETH", "SOL", "BTC"])
                == ["ETH", "BTC"])
    }

    @Test("往下拖落在目标那一行之后，往上拖落在它之前")
    func draggingLandsOnTheTarget() {
        // 往下拖：BTC 压到 ETH 上，就换到 ETH 原来的位置。
        #expect(CoinOrder.moving("BTC", onto: "ETH", in: ["BTC", "ETH", "SOL"])
                == ["ETH", "BTC", "SOL"])
        #expect(CoinOrder.moving("BTC", onto: "SOL", in: ["BTC", "ETH", "SOL"])
                == ["ETH", "SOL", "BTC"])
        // 往上拖：SOL 压到 BTC 上，落到 BTC 之前。
        #expect(CoinOrder.moving("SOL", onto: "BTC", in: ["BTC", "ETH", "SOL"])
                == ["SOL", "BTC", "ETH"])
    }

    @Test("只有两个币种时也能换位置")
    func twoCoinsSwap() {
        // 「永远插在目标之前」的写法在这里原地不动，两个币种就再也调不过来。
        #expect(CoinOrder.moving("BTC", onto: "ETH", in: ["BTC", "ETH"]) == ["ETH", "BTC"])
        #expect(CoinOrder.moving("ETH", onto: "BTC", in: ["BTC", "ETH"]) == ["ETH", "BTC"])
    }

    @Test("拖到自己身上、或拖到不存在的币上，名单不动")
    func draggingNowhereKeepsTheList() {
        let coins = ["BTC", "ETH", "SOL"]
        #expect(CoinOrder.moving("BTC", onto: "BTC", in: coins) == coins)
        #expect(CoinOrder.moving("BTC", onto: "DOGE", in: coins) == coins)
        #expect(CoinOrder.moving("DOGE", onto: "BTC", in: coins) == coins)
    }
}

@Suite("新字段的兼容")
struct MigrationTests {
    @Test("旧文件里的 primary 变成菜单栏名单")
    func primaryBecomesTheList() throws {
        let json = #"{"coins":["BTC","ETH"],"primary":"ETH","currency":"USD","interval":10,"rules":[]}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(settings.menuBarCoins == ["ETH"])
        #expect(settings.source == .binance)
        #expect(settings.proxyMode == .direct)
    }

    @Test("菜单栏名单里的币种已经删掉时一并清掉")
    func dropsCoinsThatAreGone() throws {
        let json = #"{"coins":["BTC","SOL"],"menuBarCoins":["ETH"],"rules":[]}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        // 全没了就是空：菜单栏会显示面板第一个，名单不必假装选了它。
        #expect(settings.menuBarCoins.isEmpty)
    }

    @Test("不认识的数据源按币安处理")
    func unknownSourceFallsBack() throws {
        let json = #"{"coins":["BTC"],"source":"kraken","proxyMode":"custom","rules":[]}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(settings.source == .binance)
        #expect(settings.proxyMode == .custom)
    }

    @Test("写出去的设置不再带 primary")
    func noLongerWritesPrimary() throws {
        let data = try JSONEncoder().encode(AppSettings())
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("\"primary\""))
        #expect(text.contains("menuBarCoins"))
    }
}
