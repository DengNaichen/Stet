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
        (DictationProvider.openAI, "OpenAI API", "Audio capture + OpenAI transcription"),
    ])
    func dictationProviderMetadata(
        _ provider: DictationProvider,
        expectedDisplayName: String,
        expectedPipelineDescription: String
    ) {
        #expect(provider.displayName == expectedDisplayName)
        #expect(provider.pipelineDescription == expectedPipelineDescription)
    }

    @Test func historyRetentionPeriodUsesRelativeClock() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let sixDaysAgo = now.addingTimeInterval(-6 * 24 * 60 * 60)
        let eightDaysAgo = now.addingTimeInterval(-8 * 24 * 60 * 60)

        #expect(HistoryRetentionPeriod.sevenDays.includes(sixDaysAgo, relativeTo: now))
        #expect(!HistoryRetentionPeriod.sevenDays.includes(eightDaysAgo, relativeTo: now))
        #expect(HistoryRetentionPeriod.forever.includes(eightDaysAgo, relativeTo: now))
    }

    @Test func transcriptionRecordDecodesMissingMetadataAsDefault() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let json = """
        {
          "id": "F58E2B7F-42F0-46C8-97ED-4F26F1C6533F",
          "text": "hello world",
          "createdAt": "2026-03-12T12:00:00Z"
        }
        """.data(using: .utf8)!

        let record = try decoder.decode(TranscriptionRecord.self, from: json)

        #expect(record.text == "hello world")
        #expect(record.metadata == .init())
    }

    @Test func transcriptionRecordRoundTripsMetadata() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let record = TranscriptionRecord(
            text: "translated",
            createdAt: Date(timeIntervalSince1970: 1_234_567),
            metadata: .init(
                kind: .translation,
                source: .selection,
                transcriptionProvider: "openai",
                transcriptionModel: "gpt-4o-mini-transcribe",
                translationModel: "gpt-5-mini",
                rewriteModel: nil,
                targetLanguage: "English",
                focusedAppName: "Safari",
                focusedBundleID: "com.apple.Safari",
                matchedAppBranchRuleName: "Docs",
                matchedURLPattern: "example.com/*"
            )
        )

        let data = try encoder.encode(record)
        let decoded = try decoder.decode(TranscriptionRecord.self, from: data)

        #expect(decoded == record)
    }

    @Test func openAIConfigurationProvidesExpectedDefaults() {
        let configuration = OpenAIConfiguration(apiKey: "sk-test")

        #expect(configuration.baseURL.absoluteString == "https://api.openai.com/v1")
        #expect(configuration.transcriptionModel == "gpt-4o-mini-transcribe")
        #expect(configuration.translationModel == "gpt-5-mini")
        #expect(configuration.rewriteModel == "gpt-5-mini")
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
