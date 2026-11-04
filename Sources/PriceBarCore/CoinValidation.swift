import Foundation

/// What the app checks before it adds a coin: the code the user typed, and
/// whether the exchange knows it.
public enum CoinValidation {
    /// The code as an exchange writes it: "btc " and "BTC" are the same coin.
    public static func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    /// Why the coin cannot be added without asking the exchange, or nil when
    /// it is worth asking.
    public static func problem(coin: String, existing: [String]) -> String? {
        if coin.isEmpty { return "请输入币种代号" }
        if existing.contains(coin) { return "已经添加过 \(coin)" }
        return nil
    }

    /// Why the coin cannot be added, once the exchange has answered, or nil
    /// when it can.
    public static func problem(coin: String, knownToExchange: Bool) -> String? {
        knownToExchange ? nil : "交易所没有 \(coin)USDT 这个交易对"
    }
}
