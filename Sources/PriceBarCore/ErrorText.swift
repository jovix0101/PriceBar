import Foundation

/// A network failure in words that say what went wrong.
///
/// URLSession's own messages are the system's, in English, and name the
/// mechanism rather than the cause: "A TLS error caused the secure connection
/// to fail" is what a blocked exchange looks like from here, and it reads
/// like a bug in the app. The codes that a price display actually meets are
/// named, and anything else is passed through rather than guessed at.
public func describe(_ error: Error) -> String {
    if let priceError = error as? PriceError {
        return priceError.errorDescription ?? PriceError.noData.localizedDescription
    }
    let nsError = error as NSError
    guard nsError.domain == NSURLErrorDomain else { return nsError.localizedDescription }

    switch nsError.code {
    case NSURLErrorTimedOut:
        return "请求超时，网络可能不通"
    case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed:
        return "找不到这台服务器，可能被拦住了"
    case NSURLErrorCannotConnectToHost:
        return "连不上服务器，可能被拦住了"
    case NSURLErrorNetworkConnectionLost:
        return "连接中途断开"
    case NSURLErrorNotConnectedToInternet:
        return "这台电脑没有连上网"
    case NSURLErrorSecureConnectionFailed:
        return "安全连接失败，域名可能被拦住了"
    case NSURLErrorCancelled:
        return "请求已取消"
    default:
        return "\(nsError.localizedDescription)（\(nsError.code)）"
    }
}
