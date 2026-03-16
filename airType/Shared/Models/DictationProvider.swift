import Foundation

enum DictationProvider: String, CaseIterable, Identifiable, Sendable {
    case openAI = "openai"

    var id: Self { self }

    var displayName: String {
        "OpenAI API"
    }

    var pipelineDescription: String {
        "Audio capture + OpenAI transcription"
    }
}
