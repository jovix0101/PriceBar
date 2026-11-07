import Foundation

/// Which coins still need an HTTP read, and how its answer and the pushed
/// prices fold into what the panel shows.
///
/// A connection that is open says nothing when a market is quiet: QQQ's
/// contract can go minutes without a trade. So a live coin that has been
/// silent for a minute is asked about once, and everything else on a live
/// connection costs no request at all.
public enum ReadPlan {
    /// How long a live coin may stay silent before it is checked.
    static let quietLimit: TimeInterval = 60
    /// A subscription to a code the exchange does not list is accepted and
    /// stays silent, so only a read can find that out; the answer holds for
    /// a few minutes.
    static let notListedLimit: TimeInterval = 300

    public typealias Rows = (quotes: [Quote], missing: [String: PriceAPI.Absence])

    /// The coins this refresh should ask about.
    public static func coins(
        _ coins: [String], live: Set<String>, seen: [String: Date],
        notListed: [String: Date], now: Date
    ) -> [String] {
        coins.filter { coin in
            guard live.contains(coin) else { return true }
            if let at = notListed[coin], now.timeIntervalSince(at) < notListedLimit { return false }
            guard let at = seen[coin] else { return true }
            return now.timeIntervalSince(at) >= quietLimit
        }
    }

    /// Folds in the answer about `asked`. Coins that were not asked about
    /// keep their rows. A live coin whose check could not get through keeps
    /// the price it has: the connection is still the better witness.
    public static func merged(
        coins: [String], asked: [String], reading: PriceAPI.Reading,
        quotes: [Quote], missing: [String: PriceAPI.Absence], live: Set<String>
    ) -> Rows {
        var prices = Dictionary(quotes.map { ($0.coin, $0) }, uniquingKeysWith: { _, last in last })
        var absent = missing
        for coin in asked {
            prices[coin] = nil
            absent[coin] = nil
        }
        for quote in reading.quotes { prices[quote.coin] = quote }
        for (coin, why) in reading.missing {
            if case .unreachable = why, live.contains(coin),
               let kept = quotes.first(where: { $0.coin == coin }) {
                prices[coin] = kept
            } else {
                absent[coin] = why
            }
        }
        return (coins.compactMap { prices[$0] }, absent.filter { coins.contains($0.key) })
    }

    /// Folds in prices the connection pushed. A price is the end of any
    /// reason the coin had for being missing.
    public static func pushed(
        _ incoming: [Quote], coins: [String],
        quotes: [Quote], missing: [String: PriceAPI.Absence]
    ) -> Rows {
        var prices = Dictionary(quotes.map { ($0.coin, $0) }, uniquingKeysWith: { _, last in last })
        var absent = missing
        for quote in incoming {
            prices[quote.coin] = quote
            absent[quote.coin] = nil
        }
        return (coins.compactMap { prices[$0] }, absent)
    }
}
