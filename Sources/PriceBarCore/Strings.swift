import Foundation

/// The two languages the app is written in.
public enum Language: String, Codable, CaseIterable, Sendable {
    case english = "en"
    case chinese = "zh"

    /// A language is chosen by reading its own name, whatever the app is
    /// showing at the time: "English" reads as English in either language.
    public var label: String {
        switch self {
        case .english: "English"
        case .chinese: "中文"
        }
    }
}

/// Every word the app says, in one language.
///
/// A value, not a lookup table reached from a global: a view holds the one it
/// was given and reads its words off it, so changing the language redraws
/// everything by itself and nothing has to be told that it happened.
public struct Strings: Sendable {
    public let language: Language

    public init(_ language: Language = .english) {
        self.language = language
    }

    /// The English or the Chinese of a pair.
    ///
    /// Written where the words are used rather than in a key table elsewhere:
    /// a sentence and its translation sit on one line, and neither can drift
    /// out of sight of the other.
    public func pick(_ english: String, _ chinese: String) -> String {
        language == .chinese ? chinese : english
    }

    public var isChinese: Bool { language == .chinese }
}

// MARK: - Markets and metrics

extension Strings {
    /// What a market is called where there is room: "Spot", "Perpetual".
    public func label(_ market: Market) -> String {
        switch market {
        case .spot: pick("Spot", "现货")
        case .perpetual: pick("Perpetual", "永续合约")
        }
    }

    /// The same market where there is not: the tag beside a code in the panel.
    public func shortLabel(_ market: Market) -> String {
        switch market {
        case .spot: pick("Spot", "现货")
        case .perpetual: pick("Perp", "合约")
        }
    }

    /// What a rule watches.
    public func label(_ metric: Metric) -> String {
        switch metric {
        case .price: pick("Price", "价格")
        case .change: pick("24h change", "24h 涨跌幅")
        }
    }

    /// Which colour means a rise.
    public func label(_ colors: ChangeColors) -> String {
        switch colors {
        case .greenUp: pick("Green up", "绿涨红跌")
        case .redUp: pick("Red up", "红涨绿跌")
        }
    }

    /// What colour the menu bar writes the price in.
    public func label(_ tint: MenuBarTint) -> String {
        switch tint {
        case .automatic: pick("Auto", "自动")
        case .dark: pick("Dark", "深色")
        case .light: pick("Light", "浅色")
        case .change: pick("Change", "随涨跌")
        }
    }

    /// How the app reaches the exchange.
    public func label(_ mode: ProxyMode) -> String {
        switch mode {
        case .direct: pick("Direct", "直连")
        case .system: pick("System", "跟随系统")
        case .custom: pick("Custom", "自定义")
        }
    }
}

// MARK: - What went wrong

extension Strings {
    public var timedOut: String {
        pick("The request timed out. The network may be blocked.",
             "请求超时，网络可能不通")
    }

    public var hostNotFound: String {
        pick("No such server. It may be blocked.",
             "找不到这台服务器，可能被拦住了")
    }

    public var cannotConnect: String {
        pick("Can't reach the server. It may be blocked.",
             "连不上服务器，可能被拦住了")
    }

    public var connectionLost: String {
        pick("The connection dropped.", "连接中途断开")
    }

    public var notOnline: String {
        pick("This Mac is not online.", "这台电脑没有连上网")
    }

    public var secureConnectionFailed: String {
        pick("The secure connection failed. The host may be blocked.",
             "安全连接失败，域名可能被拦住了")
    }

    public var cancelled: String {
        pick("The request was cancelled.", "请求已取消")
    }

    /// A failure with no name of its own: the system's words, and its code.
    public func systemError(_ message: String, code: Int) -> String {
        isChinese ? "\(message)（\(code)）" : "\(message) (\(code))"
    }

    public var noData: String {
        pick("No price data came back.", "没有拿到价格数据")
    }

    public func badResponse(_ code: Int) -> String {
        pick("The price API answered HTTP \(code).", "行情接口返回 HTTP \(code)")
    }

    /// Why a code cannot be added without asking the exchange.
    public var typeACode: String {
        pick("Type a code.", "请输入代号")
    }

    public func alreadyAdded(_ coin: String) -> String {
        pick("\(coin) is already on the panel.", "已经添加过 \(coin)")
    }

    public func cannotReach(_ source: String, _ reason: String) -> String {
        pick("Can't reach \(source): \(reason)", "连不上 \(source)：\(reason)")
    }

    public func onlyOneMarket(_ source: String, _ code: String, _ market: Market) -> String {
        pick("\(source) lists \(code) only as a \(label(market).lowercased()), and it is already added.",
             "\(source) 只有 \(code) 的\(shortLabel(market))，已经添加过")
    }

    public func noSuchMarket(_ source: String, _ code: String) -> String {
        pick("\(source) lists no spot or perpetual \(code).",
             "\(source) 没有 \(code) 的现货或永续合约")
    }

    public var proxyNeedsAddress: String {
        pick("Fill in the proxy address, for example http://127.0.0.1:1080",
             "请填代理地址，例如 http://127.0.0.1:1080")
    }

    public var proxyNeedsShape: String {
        pick("Write the address as http://host:port or socks5://host:port",
             "代理地址要写成 http://主机:端口 或 socks5://主机:端口")
    }
}

// MARK: - Alert text

extension Strings {
    /// A notification's title: what crossed what.
    public func alertTitle(name: String, above: Bool, metric: Metric, threshold: String) -> String {
        switch metric {
        case .price:
            if isChinese {
                return "\(name) \(above ? "突破" : "跌破") \(threshold)"
            }
            return above ? "\(name) above \(threshold)" : "\(name) below \(threshold)"
        case .change:
            if isChinese {
                return "\(name) 24h \(above ? "涨幅超" : "跌幅超") \(threshold)"
            }
            return above
                ? "\(name) up \(threshold) in 24h"
                : "\(name) down \(threshold) in 24h"
        }
    }

    /// A notification's body: where the price is now.
    public func alertBody(price: String, change: String) -> String {
        pick("Now \(price), \(change) over 24h.", "现价 \(price)，24h \(change)")
    }
}
