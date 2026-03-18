import Foundation
import Testing

@testable import Stet

private let relayAuthentication = RelayAuthenticationContext(
    functionsBaseURL: URL(string: "https://example.supabase.co/functions/v1")!,
    publishableKey: "anon-key",
    accessToken: "access-token"
)

private func makeAudioFileURL() -> URL {
    let fileURL = TestSupport.temporaryFileURL("speech", ext: "wav")
    try? Data("audio-bytes".utf8).write(to: fileURL)
    return fileURL
}

private func makeSettingsStore(
    provider: DictationProvider = .openAI,
    executionMode: AIExecutionMode = .automatic,
    rewriteEnabled: Bool = false,
    apiKey: String? = "sk-test",
    preferredSpellings: [String] = []
) throws -> (DictationSettingsStore, TestSecretStore, UserDefaults) {
    let defaults = TestSupport.makeUserDefaults()
    let secretStore = TestSecretStore()
    defaults.set(provider.rawValue, forKey: MacPreferences.transcriptionProvider)
    defaults.set(executionMode.rawValue, forKey: MacPreferences.aiExecutionMode)
    defaults.set(rewriteEnabled, forKey: MacPreferences.rewriteEnabled)

    if let apiKey {
        try secretStore.saveString(
            apiKey,
            forAccount: provider == .openAI ? "openai.api_key" : "groq.api_key"
        )
    }

    let store = DictationSettingsStore(defaults: defaults, secretStore: secretStore)
    if !preferredSpellings.isEmpty {
        store.savePersonalDictionaryEnabled(true)
        store.savePersonalDictionary(preferredSpellings)
    }

    return (store, secretStore, defaults)
}

private func makeDictationService(
    settingsStore: DictationSettingsStore,
    relayAuthentication: RelayAuthenticationContext? = nil,
    directTranscriptionService: TestTranscriptionService,
    relayTranscriptionService: TestTranscriptionService,
    rewriteService: RecordingRewriteService
) -> ConfigurableSpeechService {
    let factory = DictationPipelineFactory(
        relayAuthenticationContext: {
            relayAuthentication
        },
        makeDirectTranscriptionService: { _, _ in
            directTranscriptionService
        },
        makeRelayTranscriptionService: { _, _, _, _ in
            relayTranscriptionService
        },
        makeRewriteService: { _, _ in
            rewriteService
        }
    )

    return ConfigurableSpeechService(
        settingsStore: settingsStore,
        pipelineFactory: factory,
        captureService: TestAudioCaptureService(audioFileURL: makeAudioFileURL())
    )
}

@Suite("Configurable Speech Service", .serialized)
struct ConfigurableSpeechServiceTests {
    @Test func automaticWithoutSessionRequiresOpenAIAPIKey() async {
        let defaults = TestSupport.makeUserDefaults()
        defaults.set(DictationProvider.openAI.rawValue, forKey: MacPreferences.transcriptionProvider)

        let store = DictationSettingsStore(
            defaults: defaults,
            secretStore: TestSecretStore()
        )

        let service = ConfigurableSpeechService(
            settingsStore: store,
            pipelineFactory: .live(
                relayAuthenticationContext: { nil }
            ),
            captureService: TestAudioCaptureService(audioFileURL: makeAudioFileURL())
        )

        await #expect(throws: OpenAIError.missingAPIKey(provider: .openAI)) {
            try await service.startRecording()
        }
    }

    @Test func managedModeRequiresAuthenticatedSession() async {
        let (store, _, _) = try! makeSettingsStore(executionMode: .managed)

        let service = ConfigurableSpeechService(
            settingsStore: store,
            pipelineFactory: .live(
                relayAuthenticationContext: { nil }
            ),
            captureService: TestAudioCaptureService(audioFileURL: makeAudioFileURL())
        )

        await #expect(throws: AIExecutionError.managedRequiresAuthenticatedSession) {
            try await service.startRecording()
        }
    }

    @Test func startRecordingCanBeCalledOnlyOnceUntilStopOrCancel() async throws {
        let audioFileURL = makeAudioFileURL()
        defer { try? FileManager.default.removeItem(at: audioFileURL) }
        let direct = TestTranscriptionService(result: "source")
        let relay = TestTranscriptionService(result: "relay")
        let rewrite = RecordingRewriteService()
        let (store, _, _) = try makeSettingsStore()
        let capture = TestAudioCaptureService(audioFileURL: audioFileURL)
        let service = ConfigurableSpeechService(
            settingsStore: store,
            pipelineFactory: DictationPipelineFactory(
                relayAuthenticationContext: { nil },
                makeDirectTranscriptionService: { _, _ in direct },
                makeRelayTranscriptionService: { _, _, _, _ in relay },
                makeRewriteService: { _, _ in rewrite }
            ),
            captureService: capture
        )

        try await service.startRecording()
        await #expect(throws: SpeechServiceError.alreadyRecording) {
            try await service.startRecording()
        }

        await #expect(await capture.counts().start == 1)
        await service.cancelRecording()
    }

    @Test func cancelRecordingClearsPipelineAndPreventsStop() async throws {
        let audioFileURL = makeAudioFileURL()
        let direct = TestTranscriptionService(result: "source")
        let relay = TestTranscriptionService(result: "relay")
        let rewrite = RecordingRewriteService()
        let (store, _, _) = try makeSettingsStore()
        let capture = TestAudioCaptureService(audioFileURL: audioFileURL)
        let service = ConfigurableSpeechService(
            settingsStore: store,
            pipelineFactory: DictationPipelineFactory(
                relayAuthenticationContext: { nil },
                makeDirectTranscriptionService: { _, _ in direct },
                makeRelayTranscriptionService: { _, _, _, _ in relay },
                makeRewriteService: { _, _ in rewrite }
            ),
            captureService: capture
        )

        try await service.startRecording()
        await service.cancelRecording()

        #expect(await capture.counts().cancel == 1)
        await #expect(throws: SpeechServiceError.notRecording) {
            try await service.stopRecording()
        }
    }

    @Test func automaticWithoutSessionUsesDirectPathAndLocalRewrite() async throws {
        let audioFileURL = makeAudioFileURL()
        defer { try? FileManager.default.removeItem(at: audioFileURL) }

        let direct = TestTranscriptionService(result: "source transcript")
        let relay = TestTranscriptionService(result: "relay transcript")
        let rewrite = RecordingRewriteService()
        await rewrite.setResult("rewritten transcript")
        let (store, _, _) = try makeSettingsStore(preferredSpellings: ["OpenAI", "Groq"])
        let capture = TestAudioCaptureService(audioFileURL: audioFileURL)

        let service = ConfigurableSpeechService(
            settingsStore: store,
            pipelineFactory: DictationPipelineFactory(
                relayAuthenticationContext: { nil },
                makeDirectTranscriptionService: { _, _ in direct },
                makeRelayTranscriptionService: { _, _, _, _ in relay },
                makeRewriteService: { _, _ in rewrite }
            ),
            captureService: capture
        )

        try await service.startRecording()
        let transcript = try await service.stopRecording()
        let rewriteRequests = await rewrite.recordedRequests()
        let directInvocation = await direct.lastInvocation()

        #expect(transcript == "rewritten transcript")
        #expect(directInvocation?.prompt == nil)
        #expect(await direct.callCount() == 1)
        #expect(await relay.callCount() == 0)
        #expect(await capture.counts().stop == 1)
        #expect(rewriteRequests.count == 1)
        #expect(rewriteRequests.first?.sourceText == "source transcript")
    }

    @Test func automaticWithSessionPrefersRelayEvenWhenLocalKeyExists() async throws {
        let audioFileURL = makeAudioFileURL()
        defer { try? FileManager.default.removeItem(at: audioFileURL) }

        let direct = TestTranscriptionService(result: "source")
        let relay = TestTranscriptionService(result: "relay transcript")
        let rewrite = RecordingRewriteService()
        let (store, _, _) = try makeSettingsStore(preferredSpellings: ["OpenAI", "Groq"])
        let capture = TestAudioCaptureService(audioFileURL: audioFileURL)

        let service = ConfigurableSpeechService(
            settingsStore: store,
            pipelineFactory: DictationPipelineFactory(
                relayAuthenticationContext: { relayAuthentication },
                makeDirectTranscriptionService: { _, _ in direct },
                makeRelayTranscriptionService: { _, _, _, _ in relay },
                makeRewriteService: { _, _ in rewrite }
            ),
            captureService: capture
        )

        try await service.startRecording()
        _ = try await service.stopRecording()
        let relayInvocation = await relay.lastInvocation()

        #expect(await direct.callCount() == 0)
        #expect(await relay.callCount() == 1)
        #expect(await rewrite.recordedRequests().isEmpty)
        #expect(relayInvocation?.prompt?.contains("OpenAI, Groq") == true)
        #expect(await capture.counts().stop == 1)
    }

    @Test func automaticWithSessionDoesNotFallbackAfterRelayFailure() async throws {
        let audioFileURL = makeAudioFileURL()
        defer { try? FileManager.default.removeItem(at: audioFileURL) }

        let direct = TestTranscriptionService(result: "source")
        let relay = TestTranscriptionService(outcome: .failure(TestError.expected))
        let rewrite = RecordingRewriteService()
        let (store, _, _) = try makeSettingsStore()
        let capture = TestAudioCaptureService(audioFileURL: audioFileURL)

        let service = ConfigurableSpeechService(
            settingsStore: store,
            pipelineFactory: DictationPipelineFactory(
                relayAuthenticationContext: { relayAuthentication },
                makeDirectTranscriptionService: { _, _ in direct },
                makeRelayTranscriptionService: { _, _, _, _ in relay },
                makeRewriteService: { _, _ in rewrite }
            ),
            captureService: capture
        )

        try await service.startRecording()
        await #expect(throws: TestError.expected) {
            try await service.stopRecording()
        }

        #expect(await direct.callCount() == 0)
        #expect(await relay.callCount() == 1)
    }

    @Test func relayPathBuildsPromptAndSkipsLocalRewrite() async throws {
        let audioFileURL = makeAudioFileURL()
        defer { try? FileManager.default.removeItem(at: audioFileURL) }
        var defaults = try TestSupport.makeUserDefaults()
        defaults.set(AIExecutionMode.managed.rawValue, forKey: MacPreferences.aiExecutionMode)
        defaults.set(true, forKey: MacPreferences.rewriteEnabled)

        let store = DictationSettingsStore(
            defaults: defaults,
            secretStore: TestSecretStore()
        )
        store.savePersonalDictionary(["OpenAI", "Groq"])

        let direct = TestTranscriptionService(result: "source")
        let relay = TestTranscriptionService(result: "relay transcript")
        let rewrite = RecordingRewriteService()
        let capture = TestAudioCaptureService(audioFileURL: audioFileURL)

        let service = ConfigurableSpeechService(
            settingsStore: store,
            pipelineFactory: DictationPipelineFactory(
                relayAuthenticationContext: { relayAuthentication },
                makeDirectTranscriptionService: { _, _ in direct },
                makeRelayTranscriptionService: { _, _, _, _ in relay },
                makeRewriteService: { _, _ in rewrite }
            ),
            captureService: capture
        )

        try await service.startRecording()
        let result = try await service.stopRecording()
        let relayInvocation = await relay.lastInvocation()

        #expect(result == "relay transcript")
        #expect(await relay.callCount() == 1)
        #expect(await direct.callCount() == 0)
        #expect(await rewrite.recordedRequests().isEmpty)
        #expect(relayInvocation?.prompt?.contains("OpenAI, Groq") == true)
    }

    @Test func emptyTranscriptThrowsEmptyTranscription() async throws {
        let audioFileURL = makeAudioFileURL()
        let direct = TestTranscriptionService(outcome: .success("   "))
        let relay = TestTranscriptionService(result: "relay")
        let rewrite = RecordingRewriteService()
        let (store, _, _) = try makeSettingsStore()
        let capture = TestAudioCaptureService(audioFileURL: audioFileURL)
        let service = ConfigurableSpeechService(
            settingsStore: store,
            pipelineFactory: DictationPipelineFactory(
                relayAuthenticationContext: { nil },
                makeDirectTranscriptionService: { _, _ in direct },
                makeRelayTranscriptionService: { _, _, _, _ in relay },
                makeRewriteService: { _, _ in rewrite }
            ),
            captureService: capture
        )

        try await service.startRecording()
        defer { try? FileManager.default.removeItem(at: audioFileURL) }

        await #expect(throws: SpeechServiceError.emptyTranscription) {
            try await service.stopRecording()
        }
    }

    @Test func rewriteFailureThrows() async throws {
        let audioFileURL = makeAudioFileURL()
        let direct = TestTranscriptionService(result: "source")
        let relay = TestTranscriptionService(result: "relay")
        let rewrite = RecordingRewriteService()
        await rewrite.setError(TestError.expected)
        let (store, _, _) = try makeSettingsStore(rewriteEnabled: true)
        let capture = TestAudioCaptureService(audioFileURL: audioFileURL)

        let service = ConfigurableSpeechService(
            settingsStore: store,
            pipelineFactory: DictationPipelineFactory(
                relayAuthenticationContext: { nil },
                makeDirectTranscriptionService: { _, _ in direct },
                makeRelayTranscriptionService: { _, _, _, _ in relay },
                makeRewriteService: { _, _ in rewrite }
            ),
            captureService: capture
        )

        try await service.startRecording()
        defer { try? FileManager.default.removeItem(at: audioFileURL) }

        await #expect(throws: TestError.expected) {
            try await service.stopRecording()
        }

        #expect(await direct.callCount() == 1)
        #expect(await rewrite.recordedRequests().count == 1)
    }

    @Test func transcriptionFailurePropagatesAndCannotRetryLocally() async throws {
        let audioFileURL = makeAudioFileURL()
        let direct = TestTranscriptionService(outcome: .failure(TestError.expected))
        let relay = TestTranscriptionService(result: "relay")
        let rewrite = RecordingRewriteService()
        let (store, _, _) = try makeSettingsStore()
        let capture = TestAudioCaptureService(audioFileURL: audioFileURL)
        let service = ConfigurableSpeechService(
            settingsStore: store,
            pipelineFactory: DictationPipelineFactory(
                relayAuthenticationContext: { nil },
                makeDirectTranscriptionService: { _, _ in direct },
                makeRelayTranscriptionService: { _, _, _, _ in relay },
                makeRewriteService: { _, _ in rewrite }
            ),
            captureService: capture
        )

        try await service.startRecording()
        defer { try? FileManager.default.removeItem(at: audioFileURL) }

        await #expect(throws: TestError.expected) {
            try await service.stopRecording()
        }

        #expect(await direct.callCount() == 1)
        #expect(await relay.callCount() == 0)
        #expect(await rewrite.recordedRequests().isEmpty)
    }
}

private actor TestAudioCaptureService: AudioCaptureService, AudioLevelSource {
    private let audioFileURL: URL
    private var startCount = 0
    private var stopCount = 0
    private var cancelCount = 0
    private let audioDurationSeconds: TimeInterval?

    init(audioFileURL: URL, audioDurationSeconds: TimeInterval? = 1.2) {
        self.audioFileURL = audioFileURL
        self.audioDurationSeconds = audioDurationSeconds
    }

    func startRecording() async throws {
        startCount += 1
    }

    func stopRecording() async throws -> (url: URL, duration: TimeInterval?) {
        stopCount += 1
        return (audioFileURL, audioDurationSeconds)
    }

    func cancelRecording() async {
        cancelCount += 1
    }

    func counts() -> (start: Int, stop: Int, cancel: Int) {
        (startCount, stopCount, cancelCount)
    }

    func makeAudioLevelStream() async -> AsyncStream<Double> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}

private actor TestTranscriptionService: AudioFileTranscriptionService {
    enum Outcome: Sendable {
        case success(String)
        case failure(any Error & Sendable)
    }

    private(set) var outcome: Outcome
    private var callCountValue = 0
    private var lastInvocationValue: (languageCode: String?, prompt: String?, duration: TimeInterval?)?

    init(result: String) {
        self.outcome = .success(result)
    }

    init(outcome: Outcome) {
        self.outcome = outcome
    }

    func setOutcome(_ outcome: Outcome) {
        self.outcome = outcome
    }

    func transcribe(
        audioFileAt fileURL: URL,
        languageCode: String?,
        prompt: String?,
        audioDurationSeconds: TimeInterval?
    ) async throws -> String {
        callCountValue += 1
        lastInvocationValue = (languageCode: languageCode, prompt: prompt, duration: audioDurationSeconds)
        #expect(!fileURL.path.isEmpty)

        switch outcome {
        case .success(let value):
            return value
        case .failure(let error):
            throw error
        }
    }

    func callCount() -> Int {
        callCountValue
    }

    func lastInvocation() -> (languageCode: String?, prompt: String?, duration: TimeInterval?)? {
        lastInvocationValue
    }
}
