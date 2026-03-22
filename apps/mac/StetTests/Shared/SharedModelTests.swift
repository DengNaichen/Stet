import Foundation
import Testing

@testable import Stet

@MainActor
@Suite("Shared Models")
struct SharedModelTests {
    @Test(arguments: [
        (DictationLanguageMode.automatic, "Automatic", nil as String?),
        (.mixedChineseEnglish, "Mixed Chinese + English", nil),
        (.primarilyChinese, "Primary Chinese", "zh"),
        (.primarilyEnglish, "Primary English", "en"),
    ])
    func dictationLanguageModeMetadata(
        _ mode: DictationLanguageMode,
        expectedTitle: String,
        expectedLanguageCode: String?
    ) {
        #expect(mode.title == expectedTitle)
        #expect(mode.transcriptionLanguageCode == expectedLanguageCode)
        #expect(mode.id == mode.rawValue)
    }

    @Test(arguments: [
        (DictationProvider.openAI, "OpenAI", "Audio capture + OpenAI transcription"),
        (.groq, "Groq", "Audio capture + Groq transcription"),
    ])
    func dictationProviderMetadata(
        _ provider: DictationProvider,
        expectedDisplayName: String,
        expectedPipelineDescription: String
    ) {
        #expect(provider.displayName == expectedDisplayName)
        #expect(provider.pipelineDescription == expectedPipelineDescription)
    }

    @Test func openAIConfigurationProvidesExpectedDefaults() {
        let configuration = OpenAIConfiguration(apiKey: "sk-test")

        #expect(configuration.baseURL.absoluteString == "https://api.openai.com/v1")
        #expect(configuration.transcriptionModel == "gpt-4o-mini-transcribe")
        #expect(configuration.rewriteModel == "gpt-5.4-nano-2026-03-17")
    }

    @Test func groqConfigurationProvidesExpectedDefaults() {
        let configuration = OpenAIConfiguration(apiKey: "gsk_test", provider: .groq)

        #expect(configuration.baseURL.absoluteString == "https://api.groq.com/openai/v1")
        #expect(configuration.transcriptionModel == "whisper-large-v3-turbo")
        #expect(configuration.rewriteModel == "llama-3.3-70b-versatile")
    }

    @Test func providerAwareAPIErrorDescriptionsUseActiveProviderName() {
        #expect(
            OpenAIError.api(provider: .groq, statusCode: 401, message: "Unauthorized").localizedDescription
                == "Groq API error (401): Unauthorized"
        )
        #expect(
            OpenAIError.invalidResponse(provider: .groq).localizedDescription
                == "The Groq API returned an invalid response."
        )
    }

    @Test(arguments: [
        (InteractionSoundPreset.soft, "Soft"),
        (.glass, "Glass"),
    ])
    func interactionSoundPresetTitle(_ preset: InteractionSoundPreset, expectedTitle: String) {
        #expect(preset.title == expectedTitle)
    }

    @Test(arguments: [
        (DictationState.idle, "Ready"),
        (.starting, "Starting microphone..."),
        (.listening, "Listening..."),
        (.processing, "Processing..."),
        (.result("done"), "Transcription complete"),
        (.error(.unknown(message: "boom")), "Something went wrong"),
    ])
    func dictationStateStatusText(_ state: DictationState, expectedText: String) {
        #expect(state.statusText == expectedText)
    }
}
