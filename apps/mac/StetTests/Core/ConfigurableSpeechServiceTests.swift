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
    private let relayAuthentication = RelayAuthenticationContext(
        functionsBaseURL: URL(string: "https://example.supabase.co/functions/v1")!,
        publishableKey: "anon-key",
        accessToken: "access-token"
    )

    private func makeDependencies(
        relayAuthentication: RelayAuthenticationContext? = nil,
        makeNetworkSession: @escaping @Sendable (NetworkProxySettings) -> URLSession = { _ in
            TestURLSessionFactory.makeSession()
        },
        directSpeech: ControllableSpeechService = ControllableSpeechService(),
        relaySpeech: ControllableSpeechService = ControllableSpeechService(),
        directPromptBox: CapturedPromptBox? = nil,
        relayPromptBox: CapturedPromptBox? = nil,
        rewriteService: RecordingRewriteService = RecordingRewriteService()
    ) -> ConfigurableSpeechService.Dependencies {
        .init(
            relayAuthenticationContext: { relayAuthentication },
            makeNetworkSession: makeNetworkSession,
            makeDirectSpeechService: { _, _, _, promptProvider in
                if let directPromptBox {
                    await directPromptBox.set(await promptProvider())
                }
                return directSpeech
            },
            makeRelaySpeechService: { _, _, _, _, _, promptProvider in
                if let relayPromptBox {
                    await relayPromptBox.set(await promptProvider())
                }
                return relaySpeech
            },
            makeRewriteService: { _, _ in rewriteService }
        )
    }

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

    @Test func automaticWithoutSessionRequiresOpenAIAPIKey() async {
        let defaults = TestSupport.makeUserDefaults()
        defaults.set(DictationProvider.openAI.rawValue, forKey: MacPreferences.transcriptionProvider)
        let service = ConfigurableSpeechService(
            settingsStore: DictationSettingsStore(defaults: defaults, secretStore: TestSecretStore()),
            dependencies: makeDependencies()
        )

        await #expect(throws: OpenAIError.missingAPIKey(provider: .openAI)) {
            try await service.startRecording()
        }
    }

    @Test func automaticWithoutSessionRequiresGroqAPIKey() async {
        let defaults = TestSupport.makeUserDefaults()
        defaults.set(DictationProvider.groq.rawValue, forKey: MacPreferences.transcriptionProvider)
        let service = ConfigurableSpeechService(
            settingsStore: DictationSettingsStore(defaults: defaults, secretStore: TestSecretStore()),
            dependencies: makeDependencies()
        )

        await #expect(throws: OpenAIError.missingAPIKey(provider: .groq)) {
            try await service.startRecording()
        }
    }

    @Test func managedModeRequiresAuthenticatedSession() async {
        let defaults = TestSupport.makeUserDefaults()
        defaults.set(AIExecutionMode.managed.rawValue, forKey: MacPreferences.aiExecutionMode)

        let service = ConfigurableSpeechService(
            settingsStore: DictationSettingsStore(defaults: defaults, secretStore: TestSecretStore()),
            dependencies: makeDependencies(relayAuthentication: nil)
        )

        await #expect(throws: AIExecutionError.managedRequiresAuthenticatedSession) {
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
        let directSpeech = ControllableSpeechService()
        let service = ConfigurableSpeechService(
            settingsStore: settingsStore,
            dependencies: makeDependencies(
                makeNetworkSession: { settings in
                    proxyBox.set(settings)
                    return TestURLSessionFactory.makeSession()
                },
                directSpeech: directSpeech
            )
        )

        try await service.startRecording()
        let proxy = try #require(proxyBox.get())

        #expect(proxy.mode == .custom)
        #expect(proxy.customScheme == .socks5)
        #expect(proxy.customHost == "localhost")
        #expect(proxy.customPort == 1080)
        #expect(await directSpeech.counts().start == 1)

        await service.cancelRecording()
    }

    @Test func automaticWithoutSessionUsesDirectPathAndLocalRewrite() async throws {
        let defaults = TestSupport.makeUserDefaults()
        defaults.set(DictationProvider.openAI.rawValue, forKey: MacPreferences.transcriptionProvider)
        defaults.set(true, forKey: MacPreferences.rewriteEnabled)
        let secretStore = TestSecretStore()
        try secretStore.saveString("sk-test", forAccount: "openai.api_key")
        let settingsStore = DictationSettingsStore(defaults: defaults, secretStore: secretStore)
        settingsStore.savePersonalDictionary(["OpenAI", "Groq"])

        let directSpeech = ControllableSpeechService()
        await directSpeech.setStopBehavior(.immediate("source transcript"))
        let relaySpeech = ControllableSpeechService()
        let rewriteService = RecordingRewriteService()
        await rewriteService.setResult("rewritten transcript")
        let directPromptBox = CapturedPromptBox()

        let service = ConfigurableSpeechService(
            settingsStore: settingsStore,
            dependencies: makeDependencies(
                relayAuthentication: nil,
                directSpeech: directSpeech,
                relaySpeech: relaySpeech,
                directPromptBox: directPromptBox,
                rewriteService: rewriteService
            )
        )

        try await service.startRecording()
        let result = try await service.stopRecording()
        let rewriteRequest = try #require(await rewriteService.recordedRequests().first)

        #expect(result == "rewritten transcript")
        #expect(rewriteRequest.sourceText == "source transcript")
        #expect(rewriteRequest.systemPrompt?.contains("OpenAI, Groq") == true)
        #expect(await directPromptBox.get() == nil)
        #expect(await directSpeech.counts().start == 1)
        #expect(await relaySpeech.counts().start == 0)
    }

    @Test func automaticWithSessionPrefersRelayEvenWhenLocalKeyExists() async throws {
        let defaults = TestSupport.makeUserDefaults()
        defaults.set(DictationProvider.openAI.rawValue, forKey: MacPreferences.transcriptionProvider)
        let secretStore = TestSecretStore()
        try secretStore.saveString("sk-test", forAccount: "openai.api_key")

        let directSpeech = ControllableSpeechService()
        let relaySpeech = ControllableSpeechService()
        let service = ConfigurableSpeechService(
            settingsStore: DictationSettingsStore(defaults: defaults, secretStore: secretStore),
            dependencies: makeDependencies(
                relayAuthentication: relayAuthentication,
                directSpeech: directSpeech,
                relaySpeech: relaySpeech
            )
        )

        try await service.startRecording()

        #expect(await directSpeech.counts().start == 0)
        #expect(await relaySpeech.counts().start == 1)

        await service.cancelRecording()
    }

    @Test func automaticWithSessionDoesNotFallbackAfterRelayFailure() async throws {
        let defaults = TestSupport.makeUserDefaults()
        defaults.set(DictationProvider.openAI.rawValue, forKey: MacPreferences.transcriptionProvider)
        let secretStore = TestSecretStore()
        try secretStore.saveString("sk-test", forAccount: "openai.api_key")

        let directSpeech = ControllableSpeechService()
        let relaySpeech = ControllableSpeechService()
        await relaySpeech.setStopBehavior(.fail(TestError.expected))

        let service = ConfigurableSpeechService(
            settingsStore: DictationSettingsStore(defaults: defaults, secretStore: secretStore),
            dependencies: makeDependencies(
                relayAuthentication: relayAuthentication,
                directSpeech: directSpeech,
                relaySpeech: relaySpeech
            )
        )

        try await service.startRecording()
        await #expect(throws: TestError.expected) {
            try await service.stopRecording()
        }

        #expect(await directSpeech.counts().start == 0)
        #expect(await directSpeech.counts().stop == 0)
        #expect(await relaySpeech.counts().start == 1)
        #expect(await relaySpeech.counts().stop == 1)
    }

    @Test func relayPathBuildsTranscriptionPromptAndSkipsLocalRewrite() async throws {
        let defaults = TestSupport.makeUserDefaults()
        defaults.set(AIExecutionMode.managed.rawValue, forKey: MacPreferences.aiExecutionMode)
        defaults.set(true, forKey: MacPreferences.rewriteEnabled)
        let settingsStore = DictationSettingsStore(defaults: defaults, secretStore: TestSecretStore())
        settingsStore.savePersonalDictionary(["OpenAI", "Groq"])

        let relaySpeech = ControllableSpeechService()
        await relaySpeech.setStopBehavior(.immediate("relay transcript"))
        let rewriteService = RecordingRewriteService()
        let relayPromptBox = CapturedPromptBox()

        let service = ConfigurableSpeechService(
            settingsStore: settingsStore,
            dependencies: makeDependencies(
                relayAuthentication: relayAuthentication,
                relaySpeech: relaySpeech,
                relayPromptBox: relayPromptBox,
                rewriteService: rewriteService
            )
        )

        try await service.startRecording()
        let result = try await service.stopRecording()

        #expect(result == "relay transcript")
        #expect(await rewriteService.recordedRequests().isEmpty)
        #expect(await relayPromptBox.get()?.contains("OpenAI, Groq") == true)
    }

    @Test func emptyTranscriptThrowsEmptyTranscription() async throws {
        let directSpeech = ControllableSpeechService()
        await directSpeech.setStopBehavior(.immediate("   "))
        let secretStore = TestSecretStore()
        try secretStore.saveString("sk-test", forAccount: "openai.api_key")
        let service = ConfigurableSpeechService(
            settingsStore: DictationSettingsStore(defaults: TestSupport.makeUserDefaults(), secretStore: secretStore),
            dependencies: makeDependencies(directSpeech: directSpeech)
        )

        try await service.startRecording()
        await #expect(throws: SpeechServiceError.emptyTranscription) {
            try await service.stopRecording()
        }
    }
}
