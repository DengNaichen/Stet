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
        guard !trimmedKey.isEmpty else {
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
            token: trimmedKey,
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

public struct RewriteProviderConfiguration: Sendable, Equatable {
    public let provider: DictationProvider
    public let model: String
    public let backend: RewriteExecutionBackend

    public init(
        provider: DictationProvider,
        model: String,
        backend: RewriteExecutionBackend
    ) {
        self.provider = provider
        self.model = model
        self.backend = backend
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

public enum DictationProviderDefaults {
    public nonisolated static func rewriteModel(for provider: DictationProvider) -> String {
        switch provider {
        case .openAI: return "gpt-5.6-luna"
        case .google: return "gemini-3.7-flash"
        case .anthropic: return "claude-haiku-4-5"
        case .appleIntelligence: return "apple-intelligence-refine"
        case .groq: return "openai/gpt-oss-20b"
        case .deepSeek: return "deepseek-v4-flash"
        case .qwen: return "qwen3.5-flash"
        case .glm: return "glm-4.7-flash"
        case .doubao: return "doubao-seed-2-0-mini-260428"
        case .custom: return ""
        }
    }

    public nonisolated static func availableRewriteModels(for provider: DictationProvider) -> [String] {
        return [rewriteModel(for: provider)]
    }
}

public enum DictationProviderConfigurationResolver {
    public nonisolated static func rewriteConfiguration(
        provider: DictationProvider,
        apiKey: String,
        organizationID: String? = nil,
        projectID: String? = nil,
        customModel: String? = nil,
        baseURL: URL? = nil
    ) -> RewriteProviderConfiguration {
        let model = customModel ?? DictationProviderDefaults.rewriteModel(for: provider)
        switch provider {
        case .openAI, .groq, .deepSeek, .qwen, .glm, .doubao:
            return RewriteProviderConfiguration(
                provider: provider,
                model: model,
                backend: .remote(
                    OpenAICompatibleProviderEndpointConfiguration(
                        provider: provider,
                        apiKey: apiKey,
                        organizationID: organizationID,
                        projectID: projectID
                    )
                )
            )
        case .custom:
            guard let baseURL else {
                preconditionFailure("Custom rewrite configuration requires a base URL.")
            }
            return RewriteProviderConfiguration(
                provider: provider,
                model: model,
                backend: .remote(
                    OpenAICompatibleProviderEndpointConfiguration(
                        provider: provider,
                        apiKey: apiKey,
                        baseURL: baseURL
                    )
                )
            )
        case .google:
            return RewriteProviderConfiguration(
                provider: provider,
                model: model,
                backend: .google(apiKey: apiKey)
            )
        case .anthropic:
            return RewriteProviderConfiguration(
                provider: provider,
                model: model,
                backend: .anthropic(apiKey: apiKey)
            )
        case .appleIntelligence:
            return RewriteProviderConfiguration(
                provider: provider,
                model: model,
                backend: .appleIntelligence
            )
        }
    }
}
