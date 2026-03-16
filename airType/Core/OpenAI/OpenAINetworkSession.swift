import Foundation

enum NetworkProxyMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case system
    case disabled
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            return "System"
        case .disabled:
            return "Direct"
        case .custom:
            return "Custom"
        }
    }
}

enum CustomProxyScheme: String, CaseIterable, Codable, Identifiable, Sendable {
    case http
    case https
    case socks5

    var id: String { rawValue }

    var title: String {
        rawValue.uppercased()
    }
}

struct NetworkProxySettings: Sendable {
    var mode: NetworkProxyMode
    var customScheme: CustomProxyScheme
    var customHost: String
    var customPort: Int?

    var hasCustomEndpoint: Bool {
        !customHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && customPort != nil
    }
}

enum OpenAINetworkSession {
    nonisolated static func makeSession(for settings: NetworkProxySettings) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral

        switch settings.mode {
        case .system:
            configuration.connectionProxyDictionary = nil
        case .disabled:
            configuration.connectionProxyDictionary = [
                kCFNetworkProxiesHTTPEnable as String: 0,
                kCFNetworkProxiesHTTPSEnable as String: 0,
                kCFNetworkProxiesSOCKSEnable as String: 0,
            ]
        case .custom:
            configuration.connectionProxyDictionary = makeCustomProxyDictionary(settings: settings)
        }

        return URLSession(configuration: configuration)
    }

    nonisolated private static func makeCustomProxyDictionary(settings: NetworkProxySettings) -> [AnyHashable: Any] {
        let host = settings.customHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let port = settings.customPort ?? 0

        switch settings.customScheme {
        case .http:
            return [
                kCFNetworkProxiesHTTPEnable as String: 1,
                kCFNetworkProxiesHTTPProxy as String: host,
                kCFNetworkProxiesHTTPPort as String: port,
            ]
        case .https:
            return [
                kCFNetworkProxiesHTTPSEnable as String: 1,
                kCFNetworkProxiesHTTPSProxy as String: host,
                kCFNetworkProxiesHTTPSPort as String: port,
            ]
        case .socks5:
            return [
                kCFNetworkProxiesSOCKSEnable as String: 1,
                kCFNetworkProxiesSOCKSProxy as String: host,
                kCFNetworkProxiesSOCKSPort as String: port,
            ]
        }
    }
}
