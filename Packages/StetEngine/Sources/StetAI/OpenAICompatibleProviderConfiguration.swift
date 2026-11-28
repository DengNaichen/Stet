import Foundation
import StetCore
import OpenAI

public struct OpenAICompatibleProviderEndpointConfiguration: Sendable, Equatable {
    public let provider: DictationProvider
    public let apiKey: String
    public let baseURL: URL
    public let organizationID: String?
    public let projectID: String?

    public nonisolated init(
        provider: DictationProvider,
        apiKey: String,
        baseURL: URL? = nil,
        organizationID: String? = nil,
        projectID: String? = nil
    ) {
        self.provider = provider
        self.apiKey = apiKey
        self.baseURL = baseURL ?? Self.baseURL(for: provider)
        self.organizationID = organizationID
        self.projectID = projectID
    }

    public nonisolated var supportsResponsesStore: Bool {
        provider == .openAI
    }

    nonisolated func sdkConfiguration(
        additionalHeaders: [String: String] = [:],
        timeoutInterval: TimeInterval? = nil
    ) throws -> OpenAI.Configuration {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty || provider == .custom else {
            throw OpenAIError.missingAPIKey(provider: provider)
        }

        let normalizedBaseURL =
            baseURL.hasDirectoryPath
            ? baseURL
            : baseURL.appendingPathComponent("")

        guard let components = URLComponents(url: normalizedBaseURL, resolvingAgainstBaseURL: false),
            let scheme = components.scheme,
            let host = components.host
        else {
            throw OpenAIError.invalidBaseURL(provider: provider)
        }

        var customHeaders: [String: String] = [:]

        if let projectID = trimmedValue(projectID) {
            customHeaders["OpenAI-Project"] = projectID
        }

        for (header, value) in additionalHeaders {
            if let trimmedValue = trimmedValue(value) {
                customHeaders[header] = trimmedValue
            }
        }

        return OpenAI.Configuration(
            token: trimmedKey.isEmpty ? nil : trimmedKey,
            organizationIdentifier: trimmedValue(organizationID),
            host: host,
            port: components.port ?? Self.defaultPort(for: scheme),
            scheme: scheme,
            basePath: components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath,
            timeoutInterval: timeoutInterval ?? 60,
            customHeaders: customHeaders,
            parsingOptions: Self.requiresRelaxedParsing(for: normalizedBaseURL) ? .relaxed : []
        )
    }

    public nonisolated static func baseURL(for provider: DictationProvider) -> URL {
        switch provider {
        case .openAI:
            return URL(string: "https://api.openai.com/v1")!
        case .google, .anthropic, .appleIntelligence:
            preconditionFailure("\(provider) is not an OpenAI-compatible endpoint.")
        case .groq:
            return URL(string: "https://api.groq.com/openai/v1")!
        case .deepSeek:
            return URL(string: "https://api.deepseek.com/v1")!
        case .qwen:
            return URL(string: "https://dashscope.aliyuncs.com/compatible-mode/v1")!
        case .glm:
            return URL(string: "https://open.bigmodel.cn/api/paas/v4/")!
        case .doubao:
            return URL(string: "https://ark.cn-beijing.volces.com/api/v3")!
        case .custom:
            preconditionFailure("Custom OpenAI-compatible endpoints require an explicit base URL.")
        }
    }

    public nonisolated static func isGroqBaseURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "api.groq.com" || host.hasSuffix(".groq.com")
    }

    nonisolated private static func requiresRelaxedParsing(for baseURL: URL) -> Bool {
        guard let host = baseURL.host?.lowercased() else { return false }
        return host != "api.openai.com" && !host.hasSuffix(".openai.com")
    }

    nonisolated private static func defaultPort(for scheme: String) -> Int {
        switch scheme.lowercased() {
        case "http":
            return 80
        case "https":
            return 443
        default:
            return 443
        }
    }

    nonisolated private func trimmedValue(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
        else {
            return nil
        }

        return value
    }
}

public enum RewriteExecutionBackend: Sendable, Equatable {
    case remote(OpenAICompatibleProviderEndpointConfiguration)
    case appleIntelligence
    case google(apiKey: String)
    case anthropic(apiKey: String)
}

public enum RewriteThinkingLevel: String, Codable, Sendable, Equatable, CaseIterable {
    case off
    case minimal
    case low
    case medium
    case high
    case max

    public var displayName: String {
        switch self {
        case .off: return "Off"
        case .minimal: return "Minimal"
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .max: return "Max"
        }
    }

}

public struct RewriteProviderConfiguration: Sendable, Equatable {
    public let provider: DictationProvider
    public let model: String
    public let backend: RewriteExecutionBackend
    public let thinkingLevel: RewriteThinkingLevel?

    public init(
        provider: DictationProvider,
        model: String,
        backend: RewriteExecutionBackend,
        thinkingLevel: RewriteThinkingLevel? = nil
    ) {
        self.provider = provider
        self.model = model
        self.backend = backend
        self.thinkingLevel = thinkingLevel
    }

    public nonisolated var supportsResponsesStore: Bool {
        switch backend {
        case .remote(let endpoint):
            return endpoint.supportsResponsesStore
        case .google, .anthropic, .appleIntelligence:
            return false
        }
    }
}

public enum DictationProviderConfigurationResolver {
    public static func resolve(
        provider: DictationProvider, apiKey: String, preferredModelID: String?,
        preferredThinkingLevel: RewriteThinkingLevel?, customBaseURL: String, customModelID: String,
        catalog: RewriteModelCatalog = .bundled
    ) -> RewriteProviderConfiguration? {
        if provider == .appleIntelligence {
            return RewriteProviderConfiguration(
                provider: provider, model: "apple-intelligence-refine", backend: .appleIntelligence)
        }
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if provider == .custom {
            let id = customModelID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, let url = try? OpenAICompatibleBaseURL.normalize(customBaseURL) else { return nil }
            return transportConfiguration(provider: provider, apiKey: key, model: id, baseURL: url)
        }
        guard !key.isEmpty, let id = catalog.resolvedModelID(for: provider, preferredID: preferredModelID)
        else { return nil }
        return transportConfiguration(
            provider: provider, apiKey: key, model: id,
            thinkingLevel: catalog.resolvedThinkingLevel(
                for: provider, modelID: id, preferredLevel: preferredThinkingLevel))
    }

    nonisolated static func transportConfiguration(
        provider: DictationProvider,
        apiKey: String,
        model: String,
        baseURL: URL? = nil,
        thinkingLevel: RewriteThinkingLevel? = nil
    ) -> RewriteProviderConfiguration {
        let backend: RewriteExecutionBackend
        switch provider {
        case .appleIntelligence: backend = .appleIntelligence
        case .google: backend = .google(apiKey: apiKey)
        case .anthropic: backend = .anthropic(apiKey: apiKey)
        case .openAI, .groq, .deepSeek, .qwen, .glm, .doubao, .custom:
            backend = .remote(
                OpenAICompatibleProviderEndpointConfiguration(provider: provider, apiKey: apiKey, baseURL: baseURL))
        }
        return RewriteProviderConfiguration(
            provider: provider, model: model, backend: backend, thinkingLevel: thinkingLevel)
    }
}
