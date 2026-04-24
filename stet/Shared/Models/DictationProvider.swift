import Foundation

enum DictationProvider: String, CaseIterable, Identifiable, Sendable {
    case openAI = "openai"
    case groq = "groq"
    case appleIntelligence = "apple_intelligence"

    nonisolated var id: Self { self }

    nonisolated var displayName: String {
        switch self {
        case .openAI:
            return "OpenAI"
        case .groq:
            return "Groq"
        case .appleIntelligence:
            return "Apple Intelligence"
        }
    }

    nonisolated var pipelineDescription: String {
        switch self {
        case .openAI:
            return "Audio capture + OpenAI transcription"
        case .groq:
            return "Audio capture + Groq transcription"
        case .appleIntelligence:
            return "Audio capture + Apple Intelligence refine"
        }
    }

    nonisolated var apiKeyPlaceholder: String {
        "Enter your access key"
    }

    nonisolated var requiresAPIKey: Bool {
        switch self {
        case .openAI, .groq:
            return true
        case .appleIntelligence:
            return false
        }
    }
}
