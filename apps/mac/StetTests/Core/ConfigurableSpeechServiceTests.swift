import Foundation
import Testing

@testable import Stet

private final class CapturedProxySettingsBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: NetworkProxySettings?

    func set(_ value: NetworkProxySettings) {
        lock.lock()
        defer { lock.unlock() }
        self.value = value
    }

    func get() -> NetworkProxySettings? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

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
    @Test func makeTranscriptionPromptIncludesPreferredSpellings() {
        let prompt = ConfigurableSpeechService.makeTranscriptionPrompt(
            preferredSpellings: ["OpenAI", "Groq"]
        )

        let rendered = try! #require(prompt)
        #expect(rendered.contains("OpenAI, Groq"))
    }

    @Test func makeTranscriptionPromptReturnsNilWithoutPreferredSpellings() {
        #expect(
            ConfigurableSpeechService.makeTranscriptionPrompt(preferredSpellings: []) == nil
        )
    }

    @Test func openAIProviderRequiresAPIKey() async {
        let defaults = TestSupport.makeUserDefaults()
        defaults.set(DictationProvider.openAI.rawValue, forKey: MacPreferences.transcriptionProvider)
        let service = ConfigurableSpeechService(
            settingsStore: DictationSettingsStore(defaults: defaults, secretStore: TestSecretStore())
        )

        await #expect(throws: OpenAIError.missingAPIKey(provider: .openAI)) {
            try await service.startRecording()
        }
    }

    @Test func groqProviderRequiresGroqAPIKey() async {
        let defaults = TestSupport.makeUserDefaults()
        defaults.set(DictationProvider.groq.rawValue, forKey: MacPreferences.transcriptionProvider)
        let service = ConfigurableSpeechService(
            settingsStore: DictationSettingsStore(defaults: defaults, secretStore: TestSecretStore())
        )

        await #expect(throws: OpenAIError.missingAPIKey(provider: .groq)) {
            try await service.startRecording()
        }
    }

    @Test func startRecordingUsesLoadedProxySettings() async throws {
        let defaults = TestSupport.makeUserDefaults()
        defaults.set(DictationProvider.openAI.rawValue, forKey: MacPreferences.transcriptionProvider)
        defaults.set(NetworkProxyMode.custom.rawValue, forKey: MacPreferences.proxyMode)
        defaults.set(CustomProxyScheme.socks5.rawValue, forKey: MacPreferences.customProxyScheme)
        defaults.set("localhost", forKey: MacPreferences.customProxyHost)
        defaults.set("1080", forKey: MacPreferences.customProxyPort)

        let secretStore = TestSecretStore()
        try secretStore.saveString("sk-test", forAccount: "openai.api_key")
        let settingsStore = DictationSettingsStore(defaults: defaults, secretStore: secretStore)
        let proxyBox = CapturedProxySettingsBox()
        let speech = ControllableSpeechService()
        let service = ConfigurableSpeechService(
            settingsStore: settingsStore,
            dependencies: .init(
                makeNetworkSession: { settings in
                    proxyBox.set(settings)
                    return TestURLSessionFactory.makeSession()
                },
                makeOpenAISpeechService: { _, _, _, _ in speech },
                makeRewriteService: { _, _ in RecordingRewriteService() }
            )
        )

        try await service.startRecording()
        let proxy = try #require(proxyBox.get())

        #expect(proxy.mode == .custom)
        #expect(proxy.customScheme == .socks5)
        #expect(proxy.customHost == "localhost")
        #expect(proxy.customPort == 1080)

        await service.cancelRecording()
    }

    @Test func openAIProviderSkipsTranscriptionPromptAndUsesRewriteService() async throws {
        let defaults = TestSupport.makeUserDefaults()
        defaults.set(DictationProvider.openAI.rawValue, forKey: MacPreferences.transcriptionProvider)
        defaults.set(true, forKey: MacPreferences.rewriteEnabled)
        let secretStore = TestSecretStore()
        try secretStore.saveString("sk-test", forAccount: "openai.api_key")
        let settingsStore = DictationSettingsStore(defaults: defaults, secretStore: secretStore)
        settingsStore.savePersonalDictionary(["OpenAI", "Groq"])

        let openAISpeech = ControllableSpeechService()
        await openAISpeech.setStopBehavior(.immediate("source transcript"))
        let rewriteService = RecordingRewriteService()
        await rewriteService.setResult("rewritten transcript")
        let promptBox = CapturedPromptBox()

        let service = ConfigurableSpeechService(
            settingsStore: settingsStore,
            dependencies: .init(
                makeNetworkSession: { _ in TestURLSessionFactory.makeSession() },
                makeOpenAISpeechService: { _, _, _, promptProvider in
                    await promptBox.set(await promptProvider())
                    return openAISpeech
                },
                makeRewriteService: { _, _ in rewriteService }
            )
        )

        try await service.startRecording()
        let result = try await service.stopRecording()
        let rewriteRequest = try #require(await rewriteService.recordedRequests().first)

        #expect(result == "rewritten transcript")
        #expect(rewriteRequest.sourceText == "source transcript")
        #expect(rewriteRequest.systemPrompt?.contains("OpenAI, Groq") == true)
        #expect(await promptBox.get() == nil)
    }

    @Test func groqProviderSkipsTranscriptionPrompt() async throws {
        let defaults = TestSupport.makeUserDefaults()
        defaults.set(DictationProvider.groq.rawValue, forKey: MacPreferences.transcriptionProvider)
        let secretStore = TestSecretStore()
        try secretStore.saveString("gsk-test", forAccount: "groq.api_key")
        let settingsStore = DictationSettingsStore(defaults: defaults, secretStore: secretStore)
        settingsStore.savePersonalDictionary(["OpenAI", "Groq"])

        let groqSpeech = ControllableSpeechService()
        let promptBox = CapturedPromptBox()

        let service = ConfigurableSpeechService(
            settingsStore: settingsStore,
            dependencies: .init(
                makeNetworkSession: { _ in TestURLSessionFactory.makeSession() },
                makeOpenAISpeechService: { _, _, _, promptProvider in
                    await promptBox.set(await promptProvider())
                    return groqSpeech
                },
                makeRewriteService: { _, _ in RecordingRewriteService() }
            )
        )

        try await service.startRecording()

        #expect(await promptBox.get() == nil)

        await service.cancelRecording()
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
                makeOpenAISpeechService: { _, _, _, _ in speech },
                makeRewriteService: { _, _ in RecordingRewriteService() }
            )
        )

        try await service.startRecording()
        await #expect(throws: SpeechServiceError.emptyTranscription) {
            try await service.stopRecording()
        }
    }
}
