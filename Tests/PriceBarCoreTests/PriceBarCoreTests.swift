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
        #expect(formatArrowed(0) == "")
        // Rounds to 0.00%: no arrow rather than one pointing at nothing.
        #expect(formatArrowed(0.004) == "")
        #expect(formatArrowed(-0.004) == "")
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
        #expect(settings.rotateInterval == 5)
        #expect(settings.source == .binance)
        #expect(settings.proxyMode == .direct)
        #expect(settings.currency == .usd)
        #expect(settings.interval == 10)
        #expect(settings.rules.isEmpty)
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

    @Test("空输入与重复添加不动网络")
    func rejectsBeforeAskingTheExchange() {
        #expect(CoinValidation.problem(coin: "", existing: ["BTC"]) == "请输入币种代号")
        #expect(CoinValidation.problem(coin: "BTC", existing: ["BTC", "ETH"]) == "已经添加过 BTC")
        #expect(CoinValidation.problem(coin: "SOL", existing: ["BTC"]) == nil)
    }

    @Test("交易所没有的交易对说清楚是哪个")
    func explainsAMissingPair() {
        #expect(CoinValidation.problem(coin: "NOTACOIN", knownToExchange: false)
                == "交易所没有 NOTACOINUSDT 这个交易对")
        #expect(CoinValidation.problem(coin: "SOL", knownToExchange: true) == nil)
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

@Suite("菜单栏的轮播名单")
struct MenuBarOrderTests {
    @Test("勾选时按面板顺序，不是按点击顺序")
    func addingKeepsPanelOrder() {
        #expect(MenuBarOrder.toggling("ETH", panel: ["BTC", "ETH", "SOL"], menuBar: ["SOL"])
                == ["ETH", "SOL"])
        #expect(MenuBarOrder.toggling("ETH", panel: ["BTC", "ETH", "SOL"], menuBar: [])
                == ["ETH"])
    }

    @Test("再点一次就取消")
    func togglingTwiceRemoves() {
        #expect(MenuBarOrder.toggling("BTC", panel: ["BTC", "ETH"], menuBar: ["BTC", "ETH"])
                == ["ETH"])
    }

    @Test("删掉币种时，菜单栏名单跟着收拾")
    func settledFollowsThePanel() {
        #expect(MenuBarOrder.settled(["BTC", "SOL"], panel: ["BTC", "ETH"]) == ["BTC"])
        // 一个都不剩就是空：菜单栏回落到面板第一个，但名单如实是空的。
        #expect(MenuBarOrder.settled(["SOL"], panel: ["BTC", "ETH"]) == [])
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
