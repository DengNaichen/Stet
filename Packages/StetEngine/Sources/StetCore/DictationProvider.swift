import Foundation

public enum DictationProvider: String, CaseIterable, Identifiable, Sendable {
    case openAI = "openai"
    case google = "google"
    case anthropic = "anthropic"
    case appleIntelligence = "apple_intelligence"
    case groq = "groq"
    case deepSeek = "deepseek"
    case qwen = "qwen"
    case glm = "glm"
    case doubao = "doubao"
    case custom = "custom"

    public nonisolated var id: Self { self }

    public nonisolated var displayName: String {
        switch self {
        case .openAI:
            return NSLocalizedString("OpenAI", comment: "")
        case .google:
            return NSLocalizedString("Google", comment: "")
        case .anthropic:
            return NSLocalizedString("Anthropic", comment: "")
        case .appleIntelligence:
            return NSLocalizedString("Apple Intelligence", comment: "")
        case .groq:
            return NSLocalizedString("Groq", comment: "")
        case .deepSeek:
            return NSLocalizedString("DeepSeek", comment: "")
        case .qwen:
            return NSLocalizedString("Qwen", comment: "")
        case .glm:
            return NSLocalizedString("GLM", comment: "")
        case .doubao:
            return NSLocalizedString("Doubao", comment: "")
        case .custom:
            return NSLocalizedString("Custom", comment: "")
        }
    }

    public nonisolated var pipelineDescription: String {
        switch self {
        case .openAI:
            return NSLocalizedString("Audio capture + OpenAI transcription", comment: "")
        case .google:
            return NSLocalizedString("Audio capture + Google Gemini refine", comment: "")
        case .anthropic:
            return NSLocalizedString("Audio capture + Anthropic Claude refine", comment: "")
        case .appleIntelligence:
            return NSLocalizedString("Audio capture + Apple Intelligence refine", comment: "")
        case .groq:
            return NSLocalizedString("Audio capture + Groq transcription", comment: "")
        case .deepSeek:
            return NSLocalizedString("Audio capture + DeepSeek transcription", comment: "")
        case .qwen:
            return NSLocalizedString("Audio capture + Qwen transcription", comment: "")
        case .glm:
            return NSLocalizedString("Audio capture + GLM transcription", comment: "")
        case .doubao:
            return NSLocalizedString("Audio capture + Doubao transcription", comment: "")
        case .custom:
            return NSLocalizedString("Audio capture + OpenAI-compatible refine", comment: "")
        }
    }

    public nonisolated var apiKeyPlaceholder: String {
        switch self {
        case .custom:
            return NSLocalizedString("API key (optional)", comment: "")
        case .openAI, .google, .anthropic, .appleIntelligence, .groq, .deepSeek, .qwen, .glm, .doubao:
            return NSLocalizedString("Enter your access key", comment: "")
        }
    }

    public nonisolated var requiresAPIKey: Bool {
        switch self {
        case .openAI, .groq, .deepSeek, .qwen, .glm, .doubao, .google, .anthropic:
            return true
        case .appleIntelligence, .custom:
            return false
        }
    }
}
