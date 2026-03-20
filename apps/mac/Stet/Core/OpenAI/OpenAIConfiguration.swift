import Foundation

enum TranslationTargetLanguage: String, CaseIterable, Identifiable, Codable, Sendable {
    case english
    case chineseSimplified
    case japanese
    case korean
    case spanish
    case french
    case german

    nonisolated var id: String { rawValue }

    nonisolated var title: String {
        switch self {
        case .english:
            return "English"
        case .chineseSimplified:
            return "Chinese (Simplified)"
        case .japanese:
            return "Japanese"
        case .korean:
            return "Korean"
        case .spanish:
            return "Spanish"
        case .french:
            return "French"
        case .german:
            return "German"
        }
    }

    nonisolated var instructionName: String {
        switch self {
        case .english:
            return "English"
        case .chineseSimplified:
            return "Simplified Chinese"
        case .japanese:
            return "Japanese"
        case .korean:
            return "Korean"
        case .spanish:
            return "Spanish"
        case .french:
            return "French"
        case .german:
            return "German"
        }
    }
}

struct OpenAIConfiguration: Sendable {
    struct ProviderDefaults: Sendable {
        let transcriptionModel: String
        let translationModel: String
        let rewriteModel: String
        let supportsResponsesStore: Bool
    }

    var apiKey: String
    var baseURL: URL
    var transcriptionModel: String
    var translationModel: String
    var rewriteModel: String
    var organizationID: String?
    var projectID: String?

    nonisolated init(
        apiKey: String,
        baseURL: URL = URL(string: "https://api.openai.com/v1")!,
        transcriptionModel: String = "gpt-4o-mini-transcribe",
        translationModel: String = "gpt-5-mini",
        rewriteModel: String = "gpt-5-mini",
        organizationID: String? = nil,
        projectID: String? = nil
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.transcriptionModel = transcriptionModel
        self.translationModel = translationModel
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
            translationModel: providerDefaults.translationModel,
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
                translationModel: "gpt-5-mini",
                rewriteModel: "gpt-5-mini",
                supportsResponsesStore: true
            )
        case .groq:
            return ProviderDefaults(
                transcriptionModel: "whisper-large-v3-turbo",
                translationModel: "llama-3.3-70b-versatile",
                rewriteModel: "openai/gpt-oss-120b",
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
