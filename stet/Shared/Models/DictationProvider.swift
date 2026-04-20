import Foundation

enum DictationProvider: String, CaseIterable, Identifiable, Sendable {
    case openAI = "openai"
    case groq = "groq"

    nonisolated var id: Self { self }

    nonisolated var displayName: String {
        switch self {
        case .openAI:
            return "OpenAI"
        case .groq:
            return "Groq"
        }
    }

    nonisolated var pipelineDescription: String {
        switch self {
        case .openAI:
            return "Audio capture + OpenAI transcription"
        case .groq:
            return "Audio capture + Groq transcription"
        }
    }

    nonisolated var apiKeyPlaceholder: String {
        "Enter your access key"
    }
}
