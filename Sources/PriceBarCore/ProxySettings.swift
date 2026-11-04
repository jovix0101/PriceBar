import Foundation

/// How the app reaches the exchange: straight out, the way the system is
/// set up, or through an address the user gives.
public enum ProxyMode: String, Codable, CaseIterable, Sendable {
    case direct
    case system
    case custom

    public var label: String {
        switch self {
        case .direct: "直连"
        case .system: "跟随系统"
        case .custom: "自定义"
        }
    }
}

/// The proxy the app reads prices through.
///
/// The proxy belongs to the source, not to the app: a network that can reach
/// Binance directly reaches it faster that way, and a source that is blocked
/// without a proxy is only reachable with one. So switching source is often
/// switching proxy too, which is why the setting sits beside the source.
public struct ProxySettings: Equatable, Sendable {
    public var mode: ProxyMode
    /// A host and port with a scheme: "http://127.0.0.1:1080" or
    /// "socks5://127.0.0.1:1080". Read when the mode is `custom`.
    public var address: String

    public init(mode: ProxyMode = .direct, address: String = "") {
        self.mode = mode
        self.address = address
    }

    /// A proxy address split into what Cocoa needs.
    public struct Endpoint: Equatable, Sendable {
        public let host: String
        public let port: Int
        public let isSocks: Bool
    }

    /// The address as an endpoint, or nil when it is not one yet.
    ///
    /// A bare "127.0.0.1:1080" is taken as an HTTP proxy: a local proxy app
    /// usually tunnels HTTPS by CONNECT, which an HTTP proxy entry reaches,
    /// and typing the scheme is a detail most people would rather skip.
    public var endpoint: Endpoint? {
        var text = address.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "http://" + text }

        guard let parts = URLComponents(string: text),
              let scheme = parts.scheme?.lowercased(),
              let host = parts.host, !host.isEmpty,
              let port = parts.port, (1...65535).contains(port),
              let isSocks = ProxySettings.isSocks(scheme)
        else { return nil }
        return Endpoint(host: host, port: port, isSocks: isSocks)
    }

    private static func isSocks(_ scheme: String) -> Bool? {
        switch scheme {
        case "http", "https": false
        case "socks5", "socks5h", "socks": true
        default: nil
        }
    }

    /// Why the address cannot be used, or nil when it can.
    public var problem: String? {
        guard mode == .custom else { return nil }
        if address.trimmingCharacters(in: .whitespaces).isEmpty {
            return "请填代理地址，例如 http://127.0.0.1:1080"
        }
        guard endpoint != nil else {
            return "代理地址要写成 http://主机:端口 或 socks5://主机:端口"
        }
        return nil
    }

    /// A session that reaches the network this way.
    ///
    /// `direct` turns each kind of proxy off by name rather than leaving the
    /// dictionary empty: an empty dictionary is a request to go and look up
    /// the system's setting, which is the opposite of what it says.
    public func session(timeout: TimeInterval = 7) -> URLSession {
        URLSession(configuration: configuration(timeout: timeout))
    }

    /// The settings a session reaching the network this way needs.
    public func configuration(timeout: TimeInterval = 7) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout * 2
        // A menu bar that waits for the network to come back would sit on a
        // stale price without saying so; failing is the better answer.
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData

        switch mode {
        case .system:
            break
        case .direct:
            configuration.connectionProxyDictionary = [
                "HTTPEnable": 0, "HTTPSEnable": 0, "SOCKSEnable": 0,
            ]
        case .custom:
            if let endpoint {
                configuration.connectionProxyDictionary = endpoint.isSocks
                    ? ["SOCKSEnable": 1, "SOCKSProxy": endpoint.host, "SOCKSPort": endpoint.port]
                    : [
                        "HTTPEnable": 1, "HTTPProxy": endpoint.host, "HTTPPort": endpoint.port,
                        "HTTPSEnable": 1, "HTTPSProxy": endpoint.host, "HTTPSPort": endpoint.port,
                    ]
            }
        }
        return configuration
    }
}
