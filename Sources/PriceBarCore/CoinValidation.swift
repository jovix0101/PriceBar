import Foundation

/// What the app checks before it adds a code: the code the user typed, and
/// which of the exchange's markets list it.
public enum CoinValidation {
    /// The code as an exchange writes it: "btc " and "BTC" are the same coin.
    public static func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    /// Why the code cannot be added without asking the exchange, or nil when
    /// it is worth asking: a code already on the panel in every market has
    /// nothing left to add.
    public static func problem(
        coin: String,
        existing: [String],
        strings: Strings = Strings()
    ) -> String? {
        if coin.isEmpty { return strings.typeACode }
        let added = Market.allCases.allSatisfy { market in
            existing.contains(Instrument(code: coin, market: market).id)
        }
        if added { return strings.alreadyAdded(coin) }
        return nil
    }

    /// One market the popover can offer for a code.
    public struct Choice: Equatable, Sendable {
        public enum State: Equatable, Sendable {
            /// Listed, and not on the panel yet.
            case available
            /// Already on the panel.
            case added
            /// The market could not be asked; a proxy may change that.
            case unreachable(String)
        }

        public var instrument: Instrument
        public var state: State

        public init(instrument: Instrument, state: State) {
            self.instrument = instrument
            self.state = state
        }
    }

    /// What to do with a code once the exchange has answered.
    public enum Decision: Equatable, Sendable {
        /// Nothing can be added, and this says why.
        case problem(String)
        /// One market lists it and there is nothing to choose: add it.
        case add(Instrument)
        /// More than one market is in play: let the user pick.
        case choose([Choice])
    }

    /// Decides from what each market answered. A market that does not list
    /// the code is not offered at all; one that could not be reached is
    /// offered greyed out, so that the user knows a proxy might bring it.
    public static func decide(
        code: String,
        existing: [String],
        reading: PriceAPI.Reading,
        source: MarketSource,
        strings: Strings = Strings()
    ) -> Decision {
        let listed = Set(reading.quotes.map(\.coin))
        let choices: [Choice] = Market.allCases.compactMap { market in
            let instrument = Instrument(code: code, market: market)
            if existing.contains(instrument.id) {
                return Choice(instrument: instrument, state: .added)
            }
            if listed.contains(instrument.id) {
                return Choice(instrument: instrument, state: .available)
            }
            if case let .unreachable(message) = reading.missing[instrument.id] {
                return Choice(instrument: instrument, state: .unreachable(message))
            }
            return nil
        }

        let available = choices.filter { $0.state == .available }
        if available.isEmpty {
            if let reason = choices.lazy.compactMap(\.unreachableReason).first {
                return .problem(strings.cannotReach(source.label, reason))
            }
            if choices.contains(where: { $0.state == .added }) {
                return .problem(strings.onlyOneMarket(
                    source.label, code, choices[0].instrument.market
                ))
            }
            return .problem(strings.noSuchMarket(source.label, code))
        }
        if choices.count == 1, let only = available.first {
            return .add(only.instrument)
        }
        return .choose(choices)
    }
}

extension CoinValidation.Choice {
    var unreachableReason: String? {
        if case let .unreachable(message) = state { return message }
        return nil
    }
}
