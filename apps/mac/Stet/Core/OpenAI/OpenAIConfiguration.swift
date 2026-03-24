import Foundation

struct DictationProviderPair: Sendable, Equatable {
    nonisolated let transcriptionProvider: DictationProvider
    nonisolated let rewriteProvider: DictationProvider
}

struct OpenAIConfiguration: Sendable {
    struct ProviderDefaults: Sendable {
        let transcriptionModel: String
        let rewriteModel: String
        let supportsResponsesStore: Bool
    }

    struct ProviderPairDefaults: Sendable, Equatable {
        let transcriptionModel: String
        let rewriteModel: String
    }

    var apiKey: String
    var baseURL: URL
    var transcriptionModel: String
    var rewriteModel: String
    var organizationID: String?
    var projectID: String?

    nonisolated init(
        apiKey: String,
        baseURL: URL = URL(string: "https://api.openai.com/v1")!,
        transcriptionModel: String = "gpt-4o-mini-transcribe",
        rewriteModel: String = "gpt-5.4-nano-2026-03-17",
        organizationID: String? = nil,
        projectID: String? = nil
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.transcriptionModel = transcriptionModel
        self.rewriteModel = rewriteModel
        self.organizationID = organizationID
        self.projectID = projectID
    }

    nonisolated init(
        apiKey: String,
        provider: DictationProvider,
        organizationID: String? = nil,
        projectID: String? = nil
    ) {
        let providerDefaults = Self.providerDefaults(for: provider)
        self.init(
            apiKey: apiKey,
            baseURL: Self.baseURL(for: provider),
            transcriptionModel: providerDefaults.transcriptionModel,
            rewriteModel: providerDefaults.rewriteModel,
            organizationID: organizationID,
            projectID: projectID
        )
    }

    nonisolated static func transcriptionConfiguration(
        apiKey: String,
        providerPair: DictationProviderPair,
        organizationID: String? = nil,
        projectID: String? = nil
    ) -> Self {
        let provider = providerPair.transcriptionProvider
        let defaults = providerDefaults(for: provider)
        let pairDefaults = supportedDefaults(for: providerPair)

        return Self(
            apiKey: apiKey,
            baseURL: baseURL(for: provider),
            transcriptionModel: pairDefaults?.transcriptionModel ?? defaults.transcriptionModel,
            rewriteModel: pairDefaults?.rewriteModel ?? defaults.rewriteModel,
            organizationID: organizationID,
            projectID: projectID
        )
    }

    nonisolated static func rewriteConfiguration(
        apiKey: String,
        providerPair: DictationProviderPair,
        organizationID: String? = nil,
        projectID: String? = nil
    ) -> Self? {
        guard let pairDefaults = supportedDefaults(for: providerPair) else {
            return nil
        }

        let provider = providerPair.rewriteProvider

        return Self(
            apiKey: apiKey,
            baseURL: baseURL(for: provider),
            transcriptionModel: pairDefaults.transcriptionModel,
            rewriteModel: pairDefaults.rewriteModel,
            organizationID: organizationID,
            projectID: projectID
        )
    }

    nonisolated var supportsResponsesStore: Bool {
        Self.providerDefaults(for: baseURL).supportsResponsesStore
    }

    nonisolated static func baseURL(for provider: DictationProvider) -> URL {
        switch provider {
        case .openAI:
            return URL(string: "https://api.openai.com/v1")!
        case .groq:
            return URL(string: "https://api.groq.com/openai/v1")!
        }
    }

    nonisolated static func providerDefaults(for provider: DictationProvider) -> ProviderDefaults {
        switch provider {
        case .openAI:
            return ProviderDefaults(
                transcriptionModel: "gpt-4o-mini-transcribe",
                rewriteModel: "gpt-5.4-nano-2026-03-17",
                supportsResponsesStore: true
            )
        case .groq:
            return ProviderDefaults(
                transcriptionModel: "whisper-large-v3-turbo",
                rewriteModel: "llama-3.3-70b-versatile",
                supportsResponsesStore: false
            )
        }
    }

    nonisolated static func supportedDefaults(
        for providerPair: DictationProviderPair
    ) -> ProviderPairDefaults? {
        switch (providerPair.transcriptionProvider, providerPair.rewriteProvider) {
        case (.openAI, .openAI):
            return ProviderPairDefaults(
                transcriptionModel: "gpt-4o-mini-transcribe",
                rewriteModel: "gpt-5.4-nano-2026-03-17"
            )
        case (.groq, .groq):
            return ProviderPairDefaults(
                transcriptionModel: "whisper-large-v3-turbo",
                rewriteModel: "llama-3.3-70b-versatile"
            )
        case (.groq, .openAI):
            return ProviderPairDefaults(
                transcriptionModel: "whisper-large-v3-turbo",
                rewriteModel: "gpt-5.4-nano-2026-03-17"
            )
        case (.openAI, .groq):
            return nil
        }
    }

    nonisolated static func isSupportedProviderPair(_ providerPair: DictationProviderPair) -> Bool {
        supportedDefaults(for: providerPair) != nil
    }

    nonisolated static func providerDefaults(for baseURL: URL) -> ProviderDefaults {
        if isGroqBaseURL(baseURL) {
            return providerDefaults(for: .groq)
        }

        return providerDefaults(for: .openAI)
    }

    nonisolated static func isGroqBaseURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "api.groq.com" || host.hasSuffix(".groq.com")
    }
}
