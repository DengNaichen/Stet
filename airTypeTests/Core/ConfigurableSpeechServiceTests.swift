import Foundation
import Testing

@testable import airType

private actor CapturedPromptBox {
    private(set) var value: String?

    func set(_ value: String?) {
        self.value = value
    }

    func get() -> String? {
        value
    }
}

@MainActor
@Suite("Configurable Speech Service", .serialized)
struct ConfigurableSpeechServiceTests {
    @Test func makeTranscriptionPromptCombinesDictionaryAndContext() {
        let prompt = ConfigurableSpeechService.makeTranscriptionPrompt(
            preferredSpellings: ["OpenAI", "Groq"],
            contextInstructions: "Write tersely."
        )

        let rendered = try! #require(prompt)
        #expect(rendered.contains("OpenAI, Groq"))
        #expect(rendered.contains("Write tersely."))
    }

    @Test func openAIProviderRequiresAPIKey() async {
        let defaults = TestSupport.makeUserDefaults()
        defaults.set(DictationProvider.openAI.rawValue, forKey: MacPreferences.transcriptionProvider)
        let service = ConfigurableSpeechService(
            settingsStore: DictationSettingsStore(defaults: defaults, secretStore: TestSecretStore())
        )

        await #expect(throws: OpenAIError.missingAPIKey) {
            try await service.startRecording()
        }
    }

    @Test func openAIProviderBuildsPromptAndUsesRewriteService() async throws {
        let defaults = TestSupport.makeUserDefaults()
        defaults.set(DictationProvider.openAI.rawValue, forKey: MacPreferences.transcriptionProvider)
        defaults.set(true, forKey: MacPreferences.rewriteEnabled)
        defaults.set(true, forKey: MacPreferences.appBranchEnabled)
        let secretStore = TestSecretStore()
        try secretStore.saveString("sk-test", forAccount: "openai.api_key")
        let settingsStore = DictationSettingsStore(defaults: defaults, secretStore: secretStore)
        settingsStore.savePersonalDictionary(["OpenAI", "Groq"])
        settingsStore.saveAppBranchRules([
            .init(name: "Docs", prompt: "Use docs tone for {{APP_NAME}}", urlPatterns: ["docs.example.com/*"])
        ])

        let openAISpeech = ControllableSpeechService()
        await openAISpeech.setStopBehavior(.immediate("source transcript"))
        let rewriteService = RecordingRewriteService()
        await rewriteService.setResult("rewritten transcript")
        let promptBox = CapturedPromptBox()
        let captureContextStore = CaptureContextStore()
        await captureContextStore.setContext(
            .init(bundleID: "com.apple.Safari", appName: "Safari", browserURL: "https://docs.example.com/page")
        )

        let service = ConfigurableSpeechService(
            settingsStore: settingsStore,
            captureContextStore: captureContextStore,
            dependencies: .init(
                makeNetworkSession: { _ in TestURLSessionFactory.makeSession() },
                makeOpenAISpeechService: { _, _, _, _, promptProvider in
                    await promptBox.set(await promptProvider())
                    return openAISpeech
                },
                makeRewriteService: { _, _ in rewriteService }
            )
        )

        try await service.startRecording()
        let result = try await service.stopRecording()
        let rewriteRequest = try #require(await rewriteService.recordedRequests().first)
        let capturedPrompt = try #require(await promptBox.get())

        #expect(result == "rewritten transcript")
        #expect(rewriteRequest.sourceText == "source transcript")
        #expect(rewriteRequest.systemPrompt?.contains("OpenAI, Groq") == true)
        #expect(rewriteRequest.systemPrompt?.contains("Use docs tone for Safari") == true)
        #expect(capturedPrompt.contains("OpenAI, Groq"))
        #expect(capturedPrompt.contains("Use docs tone for Safari"))
    }

    @Test func emptyTranscriptThrowsEmptyTranscription() async throws {
        let speech = ControllableSpeechService()
        await speech.setStopBehavior(.immediate("   "))
        let secretStore = TestSecretStore()
        try secretStore.saveString("sk-test", forAccount: "openai.api_key")
        let service = ConfigurableSpeechService(
            settingsStore: DictationSettingsStore(defaults: TestSupport.makeUserDefaults(), secretStore: secretStore),
            dependencies: .init(
                makeNetworkSession: { _ in TestURLSessionFactory.makeSession() },
                makeOpenAISpeechService: { _, _, _, _, _ in speech },
                makeRewriteService: { _, _ in RecordingRewriteService() }
            )
        )

        try await service.startRecording()
        await #expect(throws: SpeechServiceError.emptyTranscription) {
            try await service.stopRecording()
        }
    }
}
