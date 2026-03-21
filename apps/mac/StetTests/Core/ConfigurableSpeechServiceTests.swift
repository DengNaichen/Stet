import AVFoundation
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
    dictationLanguageMode: DictationLanguageMode = .automatic,
    preferredSpellings: [String] = []
) throws -> (DictationSettingsStore, TestSecretStore, UserDefaults) {
    let defaults = TestSupport.makeUserDefaults()
    let secretStore = TestSecretStore()
    defaults.set(provider.rawValue, forKey: MacPreferences.transcriptionProvider)
    defaults.set(executionMode.rawValue, forKey: MacPreferences.aiExecutionMode)
    defaults.set(rewriteEnabled, forKey: MacPreferences.rewriteEnabled)
    defaults.set(dictationLanguageMode.rawValue, forKey: MacPreferences.dictationLanguageMode)

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
    private actor LevelLog {
        private var levels: [Double] = []

        func append(_ level: Double) {
            levels.append(level)
        }

        func snapshot() -> [Double] {
            levels
        }
    }

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

    @Test func defaultCaptureServiceFactoryIsNotInvokedUntilRecordingStarts() async throws {
        let audioFileURL = makeAudioFileURL()
        defer { try? FileManager.default.removeItem(at: audioFileURL) }

        let direct = TestTranscriptionService(result: "source")
        let relay = TestTranscriptionService(result: "relay")
        let rewrite = RecordingRewriteService()
        let (store, _, _) = try makeSettingsStore()
        let factory = CountingAudioCaptureFactory(audioFileURL: audioFileURL)

        let service = ConfigurableSpeechService(
            settingsStore: store,
            pipelineFactory: DictationPipelineFactory(
                relayAuthenticationContext: { nil },
                makeDirectTranscriptionService: { _, _ in direct },
                makeRelayTranscriptionService: { _, _, _, _ in relay },
                makeRewriteService: { _, _ in rewrite }
            ),
            captureServiceFactory: {
                factory.makeCaptureService()
            }
        )

        #expect(factory.invocationCount == 0)
        _ = await service.makeAudioLevelStream()
        #expect(factory.invocationCount == 0)

        try await service.startRecording()

        #expect(factory.invocationCount == 1)
        await service.cancelRecording()
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

    @Test func activateRecordingWindowForwardsToCaptureService() async throws {
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
        try await service.activateRecordingWindow()

        #expect(await capture.counts().activate == 1)

        await service.cancelRecording()
    }

    @Test func audioLevelStreamSurvivesMultipleRecordingSessions() async throws {
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

        let levelLog = LevelLog()
        let stream = await service.makeAudioLevelStream()
        let levelTask = Task<Void, Never> {
            for await level in stream {
                await levelLog.append(level)
            }
        }
        defer { levelTask.cancel() }

        try await service.startRecording()
        await capture.emitAudioLevel(0.2)
        #expect(
            await TestSupport.eventuallyAsync {
                await levelLog.snapshot().contains(0.2)
            }
        )

        _ = try await service.stopRecording()
        #expect(
            await TestSupport.eventuallyAsync {
                await levelLog.snapshot().contains(0)
            }
        )

        try await service.startRecording()
        await capture.emitAudioLevel(0.6)
        #expect(
            await TestSupport.eventuallyAsync {
                await levelLog.snapshot().contains(0.6)
            }
        )

        await service.cancelRecording()
        let finalLevels = await levelLog.snapshot()
        #expect(finalLevels.contains(0.2))
        #expect(finalLevels.contains(0.6))
    }

    @Test func automaticWithoutSessionUsesDirectPathAndLocalRewrite() async throws {
        let audioFileURL = makeAudioFileURL()
        defer { try? FileManager.default.removeItem(at: audioFileURL) }

        let direct = TestTranscriptionService(result: "source transcript")
        let relay = TestTranscriptionService(result: "relay transcript")
        let rewrite = RecordingRewriteService()
        await rewrite.setResult("rewritten transcript")
        let (store, _, _) = try makeSettingsStore(
            rewriteEnabled: true,
            preferredSpellings: ["OpenAI", "Groq"]
        )
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
        #expect(directInvocation?.languageCode == nil)
        #expect(await direct.callCount() == 1)
        #expect(await relay.callCount() == 0)
        #expect(await capture.counts().stop == 1)
        #expect(rewriteRequests.count == 1)
        #expect(rewriteRequests.first?.sourceText == "source transcript")
    }

    @Test func primaryChineseModePassesLanguageBiasAndMixedContextToRewrite() async throws {
        let audioFileURL = makeAudioFileURL()
        defer { try? FileManager.default.removeItem(at: audioFileURL) }

        let direct = TestTranscriptionService(result: "Today we are reviewing this PR")
        let relay = TestTranscriptionService(result: "relay")
        let rewrite = RecordingRewriteService()
        let (store, _, _) = try makeSettingsStore(
            rewriteEnabled: true,
            dictationLanguageMode: .primarilyChinese
        )
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
        _ = try await service.stopRecording()

        let directInvocation = await direct.lastInvocation()
        let rewriteRequests = await rewrite.recordedRequests()

        #expect(directInvocation?.languageCode == "zh")
        #expect(rewriteRequests.first?.additionalUserContext?.contains("mainly dictates in Chinese") == true)
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
        #expect(relayInvocation?.prompt == nil)
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
        #expect(relayInvocation?.prompt == nil)
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

    @Test func silentAudioIsDiscardedBeforeTranscription() async throws {
        let audioFileURL = try Self.makeSilentAudioFileURL()
        defer { try? FileManager.default.removeItem(at: audioFileURL) }

        let direct = TestTranscriptionService(result: "should not be used")
        let relay = TestTranscriptionService(result: "relay")
        let rewrite = RecordingRewriteService()
        let (store, _, _) = try makeSettingsStore()
        let capture = TestAudioCaptureService(audioFileURL: audioFileURL, audioDurationSeconds: 1)
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
        await #expect(throws: SpeechServiceError.emptyTranscription) {
            try await service.stopRecording()
        }

        #expect(await direct.callCount() == 0)
        #expect(await relay.callCount() == 0)
        #expect(await rewrite.recordedRequests().isEmpty)
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

extension ConfigurableSpeechServiceTests {
    private static func makeSilentAudioFileURL() throws -> URL {
        let fileURL = TestSupport.temporaryFileURL(ext: "wav")
        let outputFormat = try #require(
            AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: TranscriptionUploadAudioFormat.macSampleRate,
                channels: TranscriptionUploadAudioFormat.macChannelCount,
                interleaved: false
            )
        )
        let audioFile = try AVAudioFile(
            forWriting: fileURL,
            settings: outputFormat.settings,
            commonFormat: outputFormat.commonFormat,
            interleaved: outputFormat.isInterleaved
        )
        let frameCount = 16_000
        let buffer = try #require(
            AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity: AVAudioFrameCount(frameCount)
            )
        )
        buffer.frameLength = AVAudioFrameCount(frameCount)
        let channelData = try #require(buffer.int16ChannelData)

        for index in 0..<frameCount {
            channelData[0][index] = 0
        }

        try audioFile.write(from: buffer)
        return fileURL
    }
}

private actor TestAudioCaptureService: AudioCaptureService, AudioLevelSource {
    private let audioFileURL: URL
    private let audioLevelBridge = AudioLevelBridge()
    private var startCount = 0
    private var activationCount = 0
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

    func activateRecordingWindow() async throws {
        activationCount += 1
    }

    func stopRecording() async throws -> (url: URL, duration: TimeInterval?) {
        stopCount += 1
        return (audioFileURL, audioDurationSeconds)
    }

    func cancelRecording() async {
        cancelCount += 1
    }

    func prewarm() async {}

    func counts() -> (start: Int, activate: Int, stop: Int, cancel: Int) {
        (startCount, activationCount, stopCount, cancelCount)
    }

    func makeAudioLevelStream() async -> AsyncStream<Double> {
        audioLevelBridge.makeStream()
    }

    func emitAudioLevel(_ level: Double) {
        audioLevelBridge.emit(level)
    }
}

private final class CountingAudioCaptureFactory: @unchecked Sendable {
    private let lock = NSLock()
    private let audioFileURL: URL
    private var invocationCountValue = 0

    init(audioFileURL: URL) {
        self.audioFileURL = audioFileURL
    }

    var invocationCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return invocationCountValue
    }

    func makeCaptureService() -> any AudioCaptureService {
        lock.lock()
        invocationCountValue += 1
        lock.unlock()
        return TestAudioCaptureService(audioFileURL: audioFileURL)
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
