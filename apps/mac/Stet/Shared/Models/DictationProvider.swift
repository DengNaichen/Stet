import Foundation

enum DictationProvider: String, CaseIterable, Identifiable, Sendable {
    case openAI = "openai"
    case groq = "groq"

    var id: Self { self }

    var displayName: String {
        switch self {
        case .openAI:
            return "OpenAI"
        case .groq:
            return "Groq"
        }
    }

    var pipelineDescription: String {
        switch self {
        case .openAI:
            return "Audio capture + OpenAI transcription"
        case .groq:
            return "Audio capture + Groq transcription"
        }
    }

    var apiKeyPlaceholder: String {
        switch self {
        case .openAI:
            return "sk-..."
        case .groq:
            return "gsk_..."
        }
    }
}
