import Foundation

enum DictationProvider: String, CaseIterable, Identifiable, Sendable {
    case openAI = "openai"
    case groq = "groq"
    case appleIntelligence = "apple_intelligence"
    case deepSeek = "deepseek"
    case qwen = "qwen"
    case glm = "glm"
    case doubao = "doubao"

    nonisolated var id: Self { self }

    nonisolated var displayName: String {
        switch self {
        case .openAI:
            return NSLocalizedString("OpenAI", comment: "")
        case .groq:
            return NSLocalizedString("Groq", comment: "")
        case .appleIntelligence:
            return NSLocalizedString("Apple Intelligence", comment: "")
        case .deepSeek:
            return NSLocalizedString("DeepSeek", comment: "")
        case .qwen:
            return NSLocalizedString("Qwen", comment: "")
        case .glm:
            return NSLocalizedString("GLM", comment: "")
        case .doubao:
            return NSLocalizedString("Doubao", comment: "")
        }
    }

    nonisolated var pipelineDescription: String {
        switch self {
        case .openAI:
            return NSLocalizedString("Audio capture + OpenAI transcription", comment: "")
        case .groq:
            return NSLocalizedString("Audio capture + Groq transcription", comment: "")
        case .appleIntelligence:
            return NSLocalizedString("Audio capture + Apple Intelligence refine", comment: "")
        case .deepSeek:
            return NSLocalizedString("Audio capture + DeepSeek transcription", comment: "")
        case .qwen:
            return NSLocalizedString("Audio capture + Qwen transcription", comment: "")
        case .glm:
            return NSLocalizedString("Audio capture + GLM transcription", comment: "")
        case .doubao:
            return NSLocalizedString("Audio capture + Doubao transcription", comment: "")
        }
    }

    nonisolated var apiKeyPlaceholder: String {
        NSLocalizedString("Enter your access key", comment: "")
    }

    nonisolated var requiresAPIKey: Bool {
        switch self {
        case .openAI, .groq, .deepSeek, .qwen, .glm, .doubao:
            return true
        case .appleIntelligence:
            return false
        }
    }
}
