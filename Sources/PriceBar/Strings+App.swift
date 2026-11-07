import Foundation
import PriceBarCore

/// The words the app's own windows say: the panel, the settings, the popovers.
///
/// Kept out of `PriceBarCore` because they name things only the views have —
/// a settings page, a toolbar, a right-click menu. The core's own words are
/// in `Strings.swift` beside the types that use them.
extension Strings {
    /// The Chinese list writes its items with a full-width comma, the
    /// English with a comma and a space.
    var listSeparator: String { pick(", ", "、") }

    /// Two sentences, one after the other: Chinese ends the first with a full
    /// stop and no space, English with a stop and a space.
    func sentence(_ first: String, _ second: String) -> String {
        "\(first)\(isChinese ? "。" : " ")\(second)"
    }
}

// MARK: - The settings window

extension Strings {
    func pageTitle(_ page: SettingsPage) -> String {
        switch page {
        case .general: pick("General", "通用")
        case .menuBar: pick("Menu bar", "菜单栏")
        case .panel: pick("Panel", "面板")
        case .source: pick("Source", "数据源")
        }
    }

    // Language
    var languageGroup: String { pick("Interface", "界面") }
    var languageLabel: String { pick("Language", "语言") }
    var languageNote: String {
        pick("The window switches the moment it is chosen.", "选完马上换，不用重启。")
    }

    // Display
    var displayGroup: String { pick("Display", "显示") }
    var currencyLabel: String { pick("Currency", "计价货币") }
    var usdLabel: String { pick("USD", "美元 USD") }
    var cnyLabel: String { pick("CNY", "人民币 CNY") }
    var changeColorsLabel: String { pick("Change colours", "涨跌颜色") }
    var ratePending: String {
        pick("The exchange rate has not arrived, so prices show — for now.",
             "汇率还没取到，价格暂时显示为 —。")
    }
    var rateSource: String {
        pick("The rate is the ECB reference rate, updated once a day.",
             "汇率用欧洲央行的参考价，每天更新一次。")
    }

    // Quotes
    var quotesGroup: String { pick("Prices", "行情") }
    var refreshLabel: String { pick("Refresh", "刷新间隔") }
    func secondsLabel(_ seconds: Int) -> String {
        pick("\(seconds) s", "\(seconds) 秒")
    }
    var oneMinuteLabel: String { pick("1 min", "1 分钟") }
    var pushNote: String {
        pick("Prices are pushed live; the interval covers any gap in the push and quiet markets.",
             "价格实时推送，刷新间隔只在推送断开或品种长时间没成交时用到。")
    }
    var linesNote: String {
        pick("The 24h lines are read when the panel opens.",
             "行情线取 24 小时，只在打开面板时更新。")
    }

    // Startup
    var startupGroup: String { pick("Startup", "启动") }
    var openAtLoginLabel: String { pick("Open at login", "登录时自动启动") }
    var loginOnNote: String {
        pick("PriceBar opens straight into the menu bar after you log in.",
             "登录后 PriceBar 会直接出现在菜单栏。")
    }
    var loginNeedsApp: String {
        pick("A login item needs the app to run as an .app.",
             "要以 .app 运行才能设开机自启。")
    }

    // Menu bar page
    var menuBarGroup: String { pick("Menu bar", "菜单栏") }
    var coinsLabel: String { pick("Coins", "显示币种") }
    var textColourLabel: String { pick("Text colour", "文字颜色") }
    var noCoinsTicked: String {
        pick("With nothing ticked, the first coin on the panel is shown.",
             "没勾选时显示面板里的第一个币种。")
    }
    var severalTicked: String {
        pick("Ticked coins sit side by side, left to right in this order.",
             "勾选的币种并排显示，从左到右就是这个顺序。")
    }
    var oneTicked: String {
        pick("The ticked coin sits in the menu bar.", "勾选的币种显示在菜单栏。")
    }
    var dragToReorder: String {
        pick("Drag the handles to reorder. The panel follows the same order.",
             "拖动左边的把手可以调顺序，这个顺序也是面板里的顺序。")
    }
    func manyCoins(_ count: Int) -> String {
        pick("The list scrolls: \(count) coins.", "币种多了列表可以滚动，共 \(count) 个。")
    }
    var tintAutomaticNote: String {
        pick("Auto: takes the menu bar's own colour, so it stays legible over any wallpaper, light or dark.",
             "自动：跟着菜单栏自己的颜色走，换壁纸、切深浅色都能看清。")
    }
    var tintChangeNote: String {
        pick("Change: each coin takes the colour of its move, the same colour as the percentage in the panel.",
             "随涨跌：每个币种按自己的涨跌着色，和面板里的百分比同一个颜色。")
    }
    var tintFlatNote: String {
        pick("A change of exactly 0 has no direction, so the menu bar colours it.",
             "涨跌幅正好为 0 时没有方向，交回系统着色。")
    }
    func tintFixed(_ label: String) -> String {
        pick("Always \(label), whatever the wallpaper does next.",
             "固定用\(label)，不随下次换壁纸变化。")
    }
    func inMenuBar(_ name: String) -> String {
        pick("\(name) in the menu bar", "\(name) 显示在菜单栏")
    }
    var shownValue: String { pick("Shown", "已选") }
    var hiddenValue: String { pick("Hidden", "未选") }

    // Panel page
    var panelGroup: String { pick("Panel", "面板") }
    var maxRowsLabel: String { pick("Rows", "最多显示") }
    func rowsChoice(_ rows: Int) -> String { pick("\(rows)", "\(rows) 行") }
    var customChoice: String { pick("Custom", "自定义") }
    var customRowsLabel: String { pick("Custom rows", "自定义行数") }
    var rowsUnit: String { pick("rows", "行") }
    var clickOpensContractLabel: String { pick("Click opens the contract", "点击币种打开合约行情") }
    var panelScrollsNote: String {
        pick("Past this many coins the panel scrolls instead of growing.",
             "币种多过这几行，面板里滚动，不挡住下面的窗口。")
    }
    func customRangeNote(_ range: ClosedRange<Int>) -> String {
        pick("Custom takes \(range.lowerBound)–\(range.upperBound) rows.",
             "自定义可设 \(range.lowerBound)–\(range.upperBound) 行。")
    }
    func clickOpensNote(_ source: String) -> String {
        pick("A click on a coin opens its contract page on \(source), in the browser.",
             "点一下面板里的币种，在浏览器打开 \(source) 的合约行情。")
    }
    var clickDoesNothingNote: String {
        pick("A click no longer opens anything; the right-click menu still does.",
             "点击面板里的币种不再跳转；右键菜单里仍能打开合约行情。")
    }

    // Source page
    var sourceGroup: String { pick("Source and proxy", "数据源与代理") }
    var sourceLabel: String { pick("Source", "数据源") }
    var proxyLabel: String { pick("Proxy", "代理") }
    var proxyAddressLabel: String { pick("Proxy address", "代理地址") }
    var connectionTestLabel: String { pick("Connection test", "连接测试") }
    var testButton: String { pick("Test", "测试") }
    func connectingTo(_ source: String) -> String {
        pick("Connecting to \(source)…", "正在连接 \(source)…")
    }
    func usuallyNeedsProxy(_ source: String) -> String {
        pick("\(source) usually needs a proxy here. Test once before relying on it.",
             "\(source) 通常要挂代理才能连上，先测一次再决定。")
    }
    func spotDirectContractProxy(_ source: String) -> String {
        pick("\(source) spot prices come through directly; contracts usually need a proxy. Test once first.",
             "\(source) 的现货能直连，合约通常要挂代理，先测一次再决定。")
    }
    var proxyAppliesToSource: String {
        pick("The proxy applies to the chosen source only.", "代理只作用于当前选中的数据源。")
    }
}

// MARK: - The panel

extension Strings {
    var readingPrices: String { pick("Reading prices…", "正在获取价格…") }
    var refreshNow: String { pick("Refresh now", "立即刷新") }
    var refreshPrices: String { pick("Refresh prices", "刷新价格") }
    var addInstrument: String { pick("Add a coin, metal or stock", "添加币种、贵金属或美股") }
    var menuBarSettings: String { pick("Menu bar settings…", "菜单栏设置…") }
    var menuBarCoinsLabel: String { pick("Coins in the menu bar", "菜单栏显示哪些币种") }
    func menuBarCoinsNow(_ summary: String) -> String {
        pick("Coins in the menu bar: \(summary)", "菜单栏显示哪些币种，现在\(summary)")
    }
    var settingsItem: String { pick("Settings…", "设置…") }
    var quitItem: String { pick("Quit PriceBar", "退出 PriceBar") }
    var settingsAndQuit: String { pick("Settings and quit", "设置与退出") }
    func alertsFor(_ name: String) -> String {
        pick("\(name) alerts", "\(name) 的提醒")
    }
    func openContractOn(_ source: String, _ code: String) -> String {
        pick("Open \(code) on \(source)", "在 \(source) 打开 \(code) 的合约行情")
    }
    func openContractHint(_ source: String) -> String {
        pick("Opens the contract page on \(source)", "打开 \(source) 的合约行情页")
    }
    func alertsMenuItem(_ name: String) -> String {
        pick("Alerts for \(name)…", "\(name) 的提醒…")
    }
    func openContractMenu(_ source: String) -> String {
        pick("Open the contract on \(source)", "在 \(source) 打开合约行情")
    }
    var removeFromMenuBar: String { pick("Remove from the menu bar", "从菜单栏移除") }
    var showInMenuBar: String { pick("Show in the menu bar", "显示在菜单栏") }
    func removeCoin(_ name: String) -> String { pick("Remove \(name)", "移除 \(name)") }

    /// A row as a screen reader says it: the coin, the price, the move.
    func rowReading(name: String, money: String, change: String, rise: Double) -> String {
        let direction = rise > 0 ? pick("up", "上涨") : (rise < 0 ? pick("down", "下跌") : pick("flat", "持平"))
        return pick(
            "\(name) \(money), \(direction) \(change) over 24 hours",
            "\(name) \(money)，24 小时\(direction) \(change)"
        )
    }

    func notListedBy(_ source: String) -> String {
        pick("Not on \(source)", "\(source) 没有")
    }
    var unreachableShort: String { pick("Can't reach", "连不上") }
    var rateLimitedHint: String {
        pick("Waiting out the limit. Leave the proxy alone — it will retry on its own.",
             "正在等待限流解除，不用改代理，稍后会自动重试")
    }
    func notListedDetail(_ source: String, _ name: String) -> String {
        pick("\(source) does not list \(name). Try another source.",
             "\(source) 没有 \(name)，换个数据源试试")
    }
    func whyThenHint(_ message: String, _ hint: String) -> String {
        sentence(message, hint)
    }
    var menuBarSummaryEmpty: String { pick("Menu bar: —", "菜单栏：—") }
    func menuBarSummary(_ names: String) -> String {
        pick("Menu bar: \(names)", "菜单栏：\(names)")
    }
}

// MARK: - Alerts popover

extension Strings {
    var noAlerts: String { pick("No alerts yet.", "还没有提醒。") }
    var notificationsOff: String {
        pick("Notifications are turned off, so alerts will not appear.",
             "系统通知被关闭了，提醒不会弹出来。")
    }
    var openNotificationSettings: String { pick("Open notification settings", "打开通知设置") }
    var watchesLabel: String { pick("Watches", "看什么") }
    var directionLabel: String { pick("Direction", "方向") }
    var aboveLabel: String { pick("Above", "高于") }
    var belowLabel: String { pick("Below", "低于") }
    var thresholdLabel: String { pick("Threshold", "阈值") }
    var thresholdDollarsNote: String {
        pick("The threshold is in US dollars, whatever the panel shows.",
             "阈值按美元填，与面板显示的货币无关。")
    }
    var thresholdPercentNote: String {
        pick("Type a positive number: below 5 means a 5% fall.",
             "填正数即可：低于 5 表示跌 5%。")
    }
    var addAlert: String { pick("Add alert", "添加提醒") }
    var reEnable: String { pick("Re-enable", "重新启用") }
    var deleteThisAlert: String { pick("Delete this alert", "删除这条提醒") }
    func deleteNamed(_ description: String) -> String {
        pick("Delete \(description)", "删除 \(description)")
    }
    /// One rule in a line: what it watches, which side, and the value.
    func ruleLine(_ metric: String, above: Bool, threshold: String) -> String {
        pick("\(metric) \(above ? "above" : "below") \(threshold)",
             "\(metric) \(above ? "高于" : "低于") \(threshold)")
    }
}

// MARK: - Adding a coin

extension Strings {
    var addTitle: String { pick("Add", "添加") }
    var codePlaceholder: String { pick("Code, e.g. SOL, XAU, AAPL", "代号，例如 SOL、XAU、AAPL") }
    var contractTracksSpot: String {
        pick("A contract tracks spot, a little apart.", "合约价跟着现货走，平时会差一点。")
    }
    var codeHint: String {
        pick("Coins: BTC, ETH. Metals: XAU, XAG. Stocks by ticker, e.g. AAPL, TSLA.",
             "币填 BTC、ETH；黄金 XAU、白银 XAG；美股填代码，如 AAPL、TSLA。")
    }
    var cancelButton: String { pick("Cancel", "取消") }
    var settledNoExpiry: String { pick("USDT settled, no expiry", "USDT 结算 · 不到期") }
    var addedLabel: String { pick("Added", "已添加") }
    func alreadyOnPanel(_ name: String) -> String {
        pick("\(name) is already on the panel", "\(name) 已经在面板里")
    }
}

// MARK: - The app's menus

extension Strings {
    var hideApp: String { pick("Hide PriceBar", "隐藏 PriceBar") }
    var editMenu: String { pick("Edit", "编辑") }
    var undoItem: String { pick("Undo", "撤销") }
    var redoItem: String { pick("Redo", "重做") }
    var cutItem: String { pick("Cut", "剪切") }
    var copyItem: String { pick("Copy", "拷贝") }
    var pasteItem: String { pick("Paste", "粘贴") }
    var selectAllItem: String { pick("Select All", "全选") }
    var priceAccessibility: String { pick("Price", "价格") }
}

// MARK: - What the store says about a failed read

extension Strings {
    func checkProxyRunning(_ address: String) -> String {
        pick("Check the proxy is running: \(address)", "检查代理是否在运行：\(address)")
    }
    func needsProxyTurnOn(_ what: String) -> String {
        pick("\(what) usually needs a proxy here. Turn one on in Settings.",
             "\(what)通常要挂代理才能连上，可以在设置里开启。")
    }
    var tryAnotherSource: String {
        pick("Try another source in Settings.", "在设置里换一个数据源试试。")
    }
    func sourceContracts(_ source: String) -> String {
        pick("\(source) contracts", "\(source) 合约")
    }
    func sourceProblem(_ source: String, _ reason: String) -> String {
        pick("\(source): \(reason)", "\(source)：\(reason)")
    }
    func failedPart(_ name: String, _ message: String) -> String {
        pick("\(name) failed: \(message)", "\(name) 失败：\(message)")
    }
    func answeredNoQuote(_ name: String) -> String {
        pick("\(name) answered, but with no quote", "\(name) 有响应，但没有报价")
    }
    func liveButReadFailed(_ name: String, _ message: String) -> String {
        pick("\(name) live push OK (price request: \(message))",
             "\(name) 实时推送正常（查询接口：\(message)）")
    }
    func sourceOK(_ source: String, _ milliseconds: Int) -> String {
        pick("\(source) OK · \(milliseconds)ms", "\(source) 正常 · \(milliseconds)ms")
    }
}
