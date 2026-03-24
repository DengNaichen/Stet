import Foundation

struct DictationProviderPair: Sendable, Equatable {
    let transcriptionProvider: DictationProvider
    let rewriteProvider: DictationProvider
}

enum DictationProviderPairPolicy {
    nonisolated static func isSupportedInSettings(_ providerPair: DictationProviderPair) -> Bool {
        switch (providerPair.transcriptionProvider, providerPair.rewriteProvider) {
        case (.openAI, .groq):
            return false
        default:
            return true
        }
    }

    nonisolated static func unsupportedSettingsMessage(for providerPair: DictationProviderPair) -> String? {
        guard !isSupportedInSettings(providerPair) else { return nil }
        return "OpenAI transcription with Groq rewrite is not supported as a default BYOK pair on Mac."
    }
}
