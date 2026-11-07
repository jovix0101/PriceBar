import Foundation

/// Keeps this app from turning a rate-limit warning into an IP ban.
///
/// Binance counts request weight against the IP, not the API key, and a
/// proxy exit address is shared with whoever else is using that node. A 429
/// is a warning to back off; continuing to poll turns it into a 418, a ban
/// that starts at two minutes and grows to three days for repeat offenders.
/// Both answers carry a `Retry-After` header with the number of seconds to
/// wait — to avoid a ban for 429, until the ban ends for 418.
///
/// One cooldown per exchange, not per host name: every host of a source is
/// reached over the same exit IP, and it is that IP the exchange limits. A
/// separate slot per source keeps a Binance ban from hiding Gate's prices.
/// The timer keeps firing through a cooldown; requests simply do not go out
/// until it ends, and the next ordinary poll picks up where it left off.
public actor RequestPacing {
    public static let shared = RequestPacing()

    /// Whether a request may be sent now, or how long it has to wait.
    public enum Decision: Sendable, Equatable {
        case proceed
        case wait(seconds: Int, code: Int)
    }

    private struct State: Sendable {
        var until: Date
        /// When the limit that set this cooldown was recorded. A request
        /// sent before it is an old echo, not proof the IP is welcome again.
        var since: Date
        var consecutive: Int
        var code: Int
    }

    private var states: [String: State] = [:]
    private let now: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    // MARK: - How long to wait

    /// The wait for one limited answer, in seconds.
    ///
    /// `Retry-After` is the exchange's own number and wins whenever it is
    /// usable. A 418 ban can run to three days, so its header is honoured
    /// in full: asking again while still banned is what lengthens bans, and
    /// the exchange has already priced repeat offences into that number.
    /// A 429 governs a one-minute weight window, so its header is capped.
    ///
    /// Where the header is missing, 429 waits out a whole one-minute weight
    /// window and 418 waits out the shortest ban the documentation names;
    /// repeat violations double that guess. A header of a second or two is
    /// not enough on a shared exit IP, whose other users keep spending
    /// weight, so each code has a floor.
    public static func waitSeconds(
        code: Int,
        retryAfter: String?,
        consecutive: Int
    ) -> Int {
        let banned = code == 418
        let fallback = banned ? 120 : 60
        let minimum = banned ? 120 : 30
        let headerCeiling = banned ? 259_200 : 300   // longest ban documented: 3 days
        let guessedCeiling = banned ? 1800 : 300

        let asked = min(
            max(Int(retryAfter?.trimmingCharacters(in: .whitespaces) ?? "") ?? 0, 0),
            headerCeiling
        )
        let base = max(asked > 0 ? asked : fallback, minimum)
        if banned, asked > 0 { return base }

        let multiplier = 1 << min(max(consecutive, 0), 10)
        return min(base * multiplier, guessedCeiling)
    }

    // MARK: - The cooldown

    /// Asked before every request. An expired cooldown leaves its strike
    /// count behind: if the next answer is another limit, the wait grows.
    public func decision(for slot: String) -> Decision {
        guard let state = states[slot] else { return .proceed }
        let remaining = Int(ceil(state.until.timeIntervalSince(now())))
        return remaining > 0 ? .wait(seconds: remaining, code: state.code) : .proceed
    }

    /// Stamps the moment a request is about to go out. A 200 answering a
    /// request sent before a limit was recorded belongs to the old wave.
    public func stamp() -> Date { now() }

    /// Records a 429 or 418 and returns how long this slot will now wait.
    @discardableResult
    public func limited(host slot: String, code: Int, retryAfter: String?) -> Int {
        // Several instruments are read side by side. Their answers come
        // from one wave and confirm one limit, so only a wave that arrives
        // after the cooldown has expired counts as another violation.
        let current = states[slot]
        let moment = now()
        let stillCooling = current.map { $0.until > moment } ?? false
        let streak = stillCooling
            ? (current?.consecutive ?? 1)
            : (current?.consecutive ?? 0) + 1
        let seconds = Self.waitSeconds(
            code: code, retryAfter: retryAfter, consecutive: streak - 1
        )
        let until = moment.addingTimeInterval(Double(seconds))
        // A weaker answer arriving late must not shorten a stronger one,
        // and a 429 must not turn a ban back into a mere warning.
        let mergedUntil = max(current?.until ?? .distantPast, until)
        let mergedCode = current?.code == 418 || code == 418 ? 418 : code
        states[slot] = State(
            until: mergedUntil,
            since: stillCooling ? (current?.since ?? moment) : moment,
            consecutive: streak,
            code: mergedCode
        )
        return max(1, Int(ceil(mergedUntil.timeIntervalSince(moment))))
    }

    /// A 200 proves the IP is welcome again, but only for a request sent
    /// after the cooldown ended. An answer already in flight when a sibling
    /// was refused is an echo of the old wave: clearing on it would let the
    /// next poll walk straight back into the ban.
    public func succeeded(host slot: String, sentAt: Date) {
        guard let state = states[slot], sentAt >= state.until else { return }
        states.removeValue(forKey: slot)
    }

    /// A new proxy is a new exit IP: bans earned by the old one say nothing
    /// about it. Switching exchanges does not reset — each source has its
    /// own slot, and a ban still running on Binance is worth remembering.
    public func reset() {
        states.removeAll()
    }
}
