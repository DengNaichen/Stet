import Foundation
import OpenAI

struct OpenAICompatibleProviderEndpointConfiguration: Sendable, Equatable {
    let provider: DictationProvider
    let apiKey: String
    let baseURL: URL
    let organizationID: String?
    let projectID: String?

    nonisolated init(
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

    nonisolated var supportsResponsesStore: Bool {
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

    nonisolated static func baseURL(for provider: DictationProvider) -> URL {
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
        }
    }

    nonisolated static func isGroqBaseURL(_ url: URL) -> Bool {
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

enum RewriteExecutionBackend: Sendable, Equatable {
    case remote(OpenAICompatibleProviderEndpointConfiguration)
    case appleIntelligence
    case google(apiKey: String)
    case anthropic(apiKey: String)
}

struct RewriteProviderConfiguration: Sendable, Equatable {
    let provider: DictationProvider
    let model: String
    let backend: RewriteExecutionBackend

    nonisolated var supportsResponsesStore: Bool {
        switch backend {
        case .remote(let endpoint):
            return endpoint.supportsResponsesStore
        case .google, .anthropic, .appleIntelligence:
            return false
        }
    }
}

enum DictationProviderDefaults {
    nonisolated static func rewriteModel(for provider: DictationProvider) -> String {
        switch provider {
        case .openAI:
            return "gpt-5.4-nano-2026-03-17"
        case .google:
            return "gemini-3.1-flash-lite-preview"
        case .anthropic:
            return "claude-haiku-4-6"
        case .appleIntelligence:
            return "apple-intelligence-refine"
        case .groq:
            return "openai/gpt-oss-20b"
        case .deepSeek:
            return "deepseek-chat"
        case .qwen:
            return "qwen-plus"
        case .glm:
            return "glm-4"
        case .doubao:
            return "doubao-seed-1-6-251015"
        }
    }
}

enum DictationProviderConfigurationResolver {
    nonisolated static func rewriteConfiguration(
        provider: DictationProvider,
        apiKey: String,
        organizationID: String? = nil,
        projectID: String? = nil,
        customModel: String? = nil
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
