import Foundation
import Testing

@testable import Stet

@MainActor
@Suite("Shared Models")
struct SharedModelTests {
    @Test(arguments: [
        (TranslationTargetLanguage.english, "English", "English"),
        (.chineseSimplified, "Chinese (Simplified)", "Simplified Chinese"),
        (.japanese, "Japanese", "Japanese"),
    ])
    func translationTargetLanguageMetadata(
        _ language: TranslationTargetLanguage,
        expectedTitle: String,
        expectedInstructionName: String
    ) {
        #expect(language.title == expectedTitle)
        #expect(language.instructionName == expectedInstructionName)
        #expect(language.id == language.rawValue)
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
        #expect(configuration.translationModel == "gpt-5-mini")
        #expect(configuration.rewriteModel == "gpt-5-mini")
    }

    @Test func groqConfigurationProvidesExpectedDefaults() {
        let configuration = OpenAIConfiguration(apiKey: "gsk_test", provider: .groq)

        #expect(configuration.baseURL.absoluteString == "https://api.groq.com/openai/v1")
        #expect(configuration.transcriptionModel == "whisper-large-v3-turbo")
        #expect(configuration.translationModel == "llama-3.3-70b-versatile")
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
        (.listening, "Listening..."),
        (.processing, "Processing..."),
        (.result("done"), "Transcription complete"),
        (.error("boom"), "Something went wrong"),
    ])
    func dictationStateStatusText(_ state: DictationState, expectedText: String) {
        #expect(state.statusText == expectedText)
    }
}
