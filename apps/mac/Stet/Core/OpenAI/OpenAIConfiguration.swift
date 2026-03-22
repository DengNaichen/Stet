import Foundation

struct OpenAIConfiguration: Sendable {
    struct ProviderDefaults: Sendable {
        let transcriptionModel: String
        let rewriteModel: String
        let supportsResponsesStore: Bool
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
