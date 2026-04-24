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
        case .groq:
            return URL(string: "https://api.groq.com/openai/v1")!
        case .appleIntelligence:
            return URL(string: "apple-intelligence://local")!
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

struct TranscriptionProviderConfiguration: Sendable, Equatable {
    let endpoint: OpenAICompatibleProviderEndpointConfiguration
    let model: String

    nonisolated var provider: DictationProvider {
        endpoint.provider
    }

    nonisolated var apiKey: String {
        endpoint.apiKey
    }
}

struct RewriteProviderConfiguration: Sendable, Equatable {
    let endpoint: OpenAICompatibleProviderEndpointConfiguration
    let model: String

    nonisolated var provider: DictationProvider {
        endpoint.provider
    }

    nonisolated var apiKey: String {
        endpoint.apiKey
    }

    nonisolated var supportsResponsesStore: Bool {
        endpoint.supportsResponsesStore
    }
}

enum DictationProviderDefaults {
    nonisolated static func transcriptionModel(for provider: DictationProvider) -> String {
        switch provider {
        case .openAI:
            return "gpt-4o-mini-transcribe"
        case .groq:
            return "whisper-large-v3-turbo"
        case .appleIntelligence:
            return "apple-intelligence"
        }
    }

    nonisolated static func rewriteModel(for provider: DictationProvider) -> String {
        switch provider {
        case .openAI:
            return "gpt-5.4-nano-2026-03-17"
        case .groq:
            return "openai/gpt-oss-20b"
        case .appleIntelligence:
            return "apple-intelligence-refine"
        }
    }
}

enum DictationProviderConfigurationResolver {
    nonisolated static func transcriptionConfiguration(
        apiKey: String,
        providerPair: DictationProviderPair,
        organizationID: String? = nil,
        projectID: String? = nil
    ) -> TranscriptionProviderConfiguration {
        let provider = providerPair.transcriptionProvider
        return TranscriptionProviderConfiguration(
            endpoint: OpenAICompatibleProviderEndpointConfiguration(
                provider: provider,
                apiKey: apiKey,
                organizationID: organizationID,
                projectID: projectID
            ),
            model: DictationProviderDefaults.transcriptionModel(for: provider)
        )
    }

    nonisolated static func rewriteConfiguration(
        apiKey: String,
        providerPair: DictationProviderPair,
        organizationID: String? = nil,
        projectID: String? = nil
    ) -> RewriteProviderConfiguration {
        let provider = providerPair.rewriteProvider
        return RewriteProviderConfiguration(
            endpoint: OpenAICompatibleProviderEndpointConfiguration(
                provider: provider,
                apiKey: apiKey,
                organizationID: organizationID,
                projectID: projectID
            ),
            model: DictationProviderDefaults.rewriteModel(for: provider)
        )
    }
}
