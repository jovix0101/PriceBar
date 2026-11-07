import Foundation

/// A network failure in words that say what went wrong.
///
/// URLSession's own messages are the system's, in English, and name the
/// mechanism rather than the cause: "A TLS error caused the secure connection
/// to fail" is what a blocked exchange looks like from here, and it reads
/// like a bug in the app. The codes that a price display actually meets are
/// named, and anything else is passed through rather than guessed at.
public func describe(_ error: Error, _ strings: Strings = Strings()) -> String {
    if let priceError = error as? PriceError {
        switch priceError {
        case .noData: return strings.noData
        case let .badResponse(code): return strings.badResponse(code)
        case let .rateLimited(code, seconds): return strings.rateLimited(code, seconds)
        case let .unreachable(message): return message
        }
    }
    let nsError = error as NSError
    guard nsError.domain == NSURLErrorDomain else { return nsError.localizedDescription }

    switch nsError.code {
    case NSURLErrorTimedOut:
        return strings.timedOut
    case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed:
        return strings.hostNotFound
    case NSURLErrorCannotConnectToHost:
        return strings.cannotConnect
    case NSURLErrorNetworkConnectionLost:
        return strings.connectionLost
    case NSURLErrorNotConnectedToInternet:
        return strings.notOnline
    case NSURLErrorSecureConnectionFailed:
        return strings.secureConnectionFailed
    case NSURLErrorCancelled:
        return strings.cancelled
    default:
        return strings.systemError(nsError.localizedDescription, code: nsError.code)
    }
}
