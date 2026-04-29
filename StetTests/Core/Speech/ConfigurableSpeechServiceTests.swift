import AVFoundation
import Foundation
import Testing

@testable import Stet

private func makeAudioFileURL() -> URL {
    let fileURL = TestSupport.temporaryFileURL("speech", ext: "wav")
    try? Data("audio-bytes".utf8).write(to: fileURL)
    return fileURL
}

private func makeSettingsStore(
    provider: DictationProvider = .openAI,
    transcriptionProvider: DictationProvider? = nil,
    rewriteProvider: DictationProvider? = nil,
    rewriteEnabled: Bool = false,
    apiKey: String? = "sk-test",
    openAIAPIKey: String? = nil,
    groqAPIKey: String? = nil,
    transcriptionPrimaryLanguage: String = "en",
    transcriptionSecondaryLanguage: String? = nil,
    preferredSpellings: [String] = []
) throws -> (DictationSettingsStore, TestSecretStore, UserDefaults) {
    let defaults = TestSupport.makeUserDefaults()
    let secretStore = TestSecretStore()
    let selectedTranscriptionProvider = transcriptionProvider ?? provider
    let selectedRewriteProvider = rewriteProvider ?? selectedTranscriptionProvider
    defaults.set(selectedTranscriptionProvider.rawValue, forKey: MacPreferences.transcriptionProvider)
    defaults.set(selectedRewriteProvider.rawValue, forKey: MacPreferences.rewriteProvider)
    defaults.set(rewriteEnabled, forKey: MacPreferences.rewriteEnabled)
    defaults.set(transcriptionPrimaryLanguage, forKey: MacPreferences.transcriptionPrimaryLanguage)
    if let transcriptionSecondaryLanguage {
        defaults.set(transcriptionSecondaryLanguage, forKey: MacPreferences.transcriptionSecondaryLanguage)
    }

    if let openAIAPIKey {
        try secretStore.saveString(openAIAPIKey, forAccount: "openai.api_key")
    }

    if let groqAPIKey {
        try secretStore.saveString(groqAPIKey, forAccount: "groq.api_key")
    }

    if let apiKey, openAIAPIKey == nil, groqAPIKey == nil {
        try secretStore.saveString(
            apiKey,
            forAccount: selectedTranscriptionProvider == .openAI ? "openai.api_key" : "groq.api_key"
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
    directTranscriptionService: TestTranscriptionService,
    rewriteService: RecordingRewriteService,
    audienceProvider: @escaping @Sendable () -> AppAudience = { .ai }
) -> ConfigurableSpeechService {
    let factory = DictationPipelineFactory(
        makeLocalTranscriptionService: {
            directTranscriptionService
        },
        makeRewriteService: { _, _ in
            rewriteService
        }
    )

    return ConfigurableSpeechService(
        settingsStore: settingsStore,
        pipelineFactory: factory,
        audienceProvider: audienceProvider,
        captureService: TestAudioCaptureService(audioFileURL: makeAudioFileURL())
    )
}

private func makeProcessedAudioResult(
    processedURL: URL,
    sourceURL: URL? = nil,
    duration: TimeInterval? = 1.2,
    shouldDiscardAsNoSpeech: Bool = false
) -> AudioPostProcessingResult {
    AudioPostProcessingResult(
        url: processedURL,
        duration: duration,
        cleanupURLs: Array(Set([processedURL, sourceURL].compactMap { $0 })),
        shouldDiscardAsNoSpeech: shouldDiscardAsNoSpeech
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

    private actor EventLog {
        private var events: [String] = []

        func append(_ event: String) {
            events.append(event)
        }

        func snapshot() -> [String] {
            events
        }
    }

    @Test func byokWithoutSessionAllowsLocalTranscriptionWhenRewriteIsDisabled() async throws {
        let defaults = TestSupport.makeUserDefaults()
        defaults.set(DictationProvider.openAI.rawValue, forKey: MacPreferences.transcriptionProvider)

        let store = DictationSettingsStore(
            defaults: defaults,
            secretStore: TestSecretStore()
        )

        let service = ConfigurableSpeechService(
            settingsStore: store,
            pipelineFactory: DictationPipelineFactory(
                makeLocalTranscriptionService: { TestTranscriptionService(result: "test") },
                makeRewriteService: { _, _ in RecordingRewriteService() }
            ),
            captureService: TestAudioCaptureService(audioFileURL: makeAudioFileURL())
        )

        try await service.startRecording()
        await service.cancelRecording()
    }

    @Test func localWhisperModelMissingFailsBeforeCaptureStarts() async throws {
        let (store, _, _) = try makeSettingsStore(
            rewriteProvider: .openAI,
            openAIAPIKey: "sk-test"
        )
        let capture = TestAudioCaptureService(audioFileURL: makeAudioFileURL())
        let service = ConfigurableSpeechService(
            settingsStore: store,
            pipelineFactory: DictationPipelineFactory(
                makeLocalTranscriptionService: {
                    throw LocalWhisperError.modelMissing(
                        expectedURL: URL(fileURLWithPath: "/tmp/ggml-large-v3-turbo-q5_0.bin")
                    )
                },
                makeRewriteService: { _, _ in RecordingRewriteService() }
            ),
            captureService: capture
        )

        await #expect(
            throws: LocalWhisperError.modelMissing(
                expectedURL: URL(fileURLWithPath: "/tmp/ggml-large-v3-turbo-q5_0.bin"))
        ) {
            try await service.startRecording()
        }

        let counts = await capture.counts()
        #expect(counts.start == 0)
    }

    @Test func defaultCaptureServiceFactoryIsNotInvokedUntilRecordingStarts() async throws {
        let audioFileURL = makeAudioFileURL()
        defer { try? FileManager.default.removeItem(at: audioFileURL) }

        let direct = TestTranscriptionService(result: "source")
        let rewrite = RecordingRewriteService()
        let (store, _, _) = try makeSettingsStore()
        let factory = CountingAudioCaptureFactory(audioFileURL: audioFileURL)

        let service = ConfigurableSpeechService(
            settingsStore: store,
            pipelineFactory: DictationPipelineFactory(
                makeLocalTranscriptionService: { direct },
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
        let rewrite = RecordingRewriteService()
        let (store, _, _) = try makeSettingsStore()
        let capture = TestAudioCaptureService(audioFileURL: audioFileURL)
        let service = ConfigurableSpeechService(
            settingsStore: store,
            pipelineFactory: DictationPipelineFactory(
                makeLocalTranscriptionService: { direct },
                makeRewriteService: { _, _ in rewrite }
            ),
            audienceProvider: { .ai },
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
        let rewrite = RecordingRewriteService()
        let (store, _, _) = try makeSettingsStore()
        let capture = TestAudioCaptureService(audioFileURL: audioFileURL)
        let service = ConfigurableSpeechService(
            settingsStore: store,
            pipelineFactory: DictationPipelineFactory(
                makeLocalTranscriptionService: { direct },
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
        let rewrite = RecordingRewriteService()
        let (store, _, _) = try makeSettingsStore()
        let capture = TestAudioCaptureService(audioFileURL: audioFileURL)
        let service = ConfigurableSpeechService(
            settingsStore: store,
            pipelineFactory: DictationPipelineFactory(
                makeLocalTranscriptionService: { direct },
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
        let rewrite = RecordingRewriteService()
        let (store, _, _) = try makeSettingsStore()
        let capture = TestAudioCaptureService(audioFileURL: audioFileURL)
        let service = ConfigurableSpeechService(
            settingsStore: store,
            pipelineFactory: DictationPipelineFactory(
                makeLocalTranscriptionService: { direct },
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

    @Test func stopRecordingCallsCaptureStoppedHookBeforeAudioPostProcessing() async throws {
        let sourceAudioURL = makeAudioFileURL()
        let processedAudioURL = TestSupport.temporaryFileURL("processed-speech", ext: "wav")
        defer {
            try? FileManager.default.removeItem(at: sourceAudioURL)
            try? FileManager.default.removeItem(at: processedAudioURL)
        }

        let direct = TestTranscriptionService(result: "source transcript")
        let rewrite = RecordingRewriteService()
        let (store, _, _) = try makeSettingsStore()
        let capture = TestAudioCaptureService(audioFileURL: sourceAudioURL)
        let eventLog = EventLog()
        let postProcessor = TestAudioPostProcessor(
            result: makeProcessedAudioResult(
                processedURL: processedAudioURL,
                sourceURL: sourceAudioURL
            ),
            onProcessAudioFile: {
                await eventLog.append("postProcess")
            }
        )

        let service = ConfigurableSpeechService(
            settingsStore: store,
            pipelineFactory: DictationPipelineFactory(
                makeLocalTranscriptionService: { direct },
                makeRewriteService: { _, _ in rewrite }
            ),
            audioPostProcessor: postProcessor,
            captureService: capture
        )

        try await service.startRecording()
        _ = try await service.stopRecording(onCaptureStopped: {
            await eventLog.append("captureStopped")
        })
        await eventLog.append("stopCompleted")

        #expect(await eventLog.snapshot() == ["captureStopped", "postProcess", "stopCompleted"])
    }

    @Test func byokUsesDirectPathAndLocalRewrite() async throws {
        let audioFileURL = makeAudioFileURL()
        defer { try? FileManager.default.removeItem(at: audioFileURL) }

        let direct = TestTranscriptionService(result: "source transcript")
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
                makeLocalTranscriptionService: { direct },
                makeRewriteService: { _, _ in rewrite }
            ),
            captureService: capture
        )

        try await service.startRecording()
        let transcript = try await service.stopRecording()
        let rewriteRequests = await rewrite.recordedRequests()
        let directInvocation = await direct.lastInvocation()

        #expect(transcript == "rewritten transcript")
        #expect(directInvocation?.prompt?.contains("OpenAI, Groq") == true)
        #expect(directInvocation?.languageCode == nil)
        #expect(await direct.callCount() == 1)
        #expect(await capture.counts().stop == 1)
        #expect(rewriteRequests.count == 1)
        #expect(rewriteRequests.first?.text == "source transcript")
    }

    @Test func startRecordingPrewarmsRewriteService() async throws {
        let (store, _, _) = try makeSettingsStore(
            rewriteProvider: .appleIntelligence,
            rewriteEnabled: true,
            apiKey: nil,
            preferredSpellings: ["Stet", "CoreML"]
        )
        let direct = TestTranscriptionService(result: "source transcript")
        let rewrite = RecordingRewriteService()
        let service = makeDictationService(
            settingsStore: store,
            directTranscriptionService: direct,
            rewriteService: rewrite
        )

        try await service.startRecording()
        try await Task.sleep(for: .milliseconds(50))

        let prewarmRequest = try #require(await rewrite.recordedPrewarmRequests().first)
        #expect(prewarmRequest.text.isEmpty)
        #expect(prewarmRequest.audience == .ai)
        #expect(prewarmRequest.preferredSpellings == ["Stet", "CoreML"])

        await service.cancelRecording()
    }

    @Test func byokHumanAudienceUsesHumanLocalCleanupPrompt() async throws {
        let audioFileURL = makeAudioFileURL()
        defer { try? FileManager.default.removeItem(at: audioFileURL) }

        let direct = TestTranscriptionService(result: "source transcript")
        let rewrite = RecordingRewriteService()
        await rewrite.setResult("rewritten transcript")
        let (store, _, _) = try makeSettingsStore(
            rewriteEnabled: true,
            preferredSpellings: ["Cursor"]
        )

        let service = ConfigurableSpeechService(
            settingsStore: store,
            pipelineFactory: DictationPipelineFactory(
                makeLocalTranscriptionService: { direct },
                makeRewriteService: { _, _ in rewrite }
            ),
            audienceProvider: { .human },
            captureService: TestAudioCaptureService(audioFileURL: audioFileURL)
        )

        try await service.startRecording()
        _ = try await service.stopRecording()

        let request = try #require(await rewrite.recordedRequests().first)
        #expect(request.audience == .human)
        #expect(request.preferredSpellings == ["Cursor"])
    }

    @Test func byokUsesAIAudiencePromptWhenTargetAppIsUnknown() async throws {
        let audioFileURL = makeAudioFileURL()
        defer { try? FileManager.default.removeItem(at: audioFileURL) }

        let direct = TestTranscriptionService(result: "source transcript")
        let rewrite = RecordingRewriteService()
        await rewrite.setResult("rewritten transcript")
        let (store, _, _) = try makeSettingsStore(
            rewriteEnabled: true,
            preferredSpellings: ["Cursor"]
        )

        let service = ConfigurableSpeechService(
            settingsStore: store,
            pipelineFactory: DictationPipelineFactory(
                makeLocalTranscriptionService: { direct },
                makeRewriteService: { _, _ in rewrite }
            ),
            audienceProvider: { .ai },
            captureService: TestAudioCaptureService(audioFileURL: audioFileURL)
        )

        try await service.startRecording()
        _ = try await service.stopRecording()

        let request = try #require(await rewrite.recordedRequests().first)
        #expect(request.audience == .ai)
        #expect(request.preferredSpellings == ["Cursor"])
    }

    @Test func byokOpenAIToOpenAIReturnsOnlyRewrittenText() async throws {
        let audioFileURL = makeAudioFileURL()
        defer { try? FileManager.default.removeItem(at: audioFileURL) }

        let direct = TestTranscriptionService(result: "raw transcript")
        let rewrite = RecordingRewriteService()
        await rewrite.setResult("rewritten transcript")
        let (store, _, _) = try makeSettingsStore(
            transcriptionProvider: .openAI,
            rewriteProvider: .openAI,
            rewriteEnabled: true,
            openAIAPIKey: "sk-test"
        )

        let service = makeDictationService(
            settingsStore: store,
            directTranscriptionService: direct,
            rewriteService: rewrite
        )

        try await service.startRecording()
        let result = try await service.stopRecording()

        #expect(result == "rewritten transcript")
        #expect(await direct.callCount() == 1)
        #expect(await rewrite.recordedRequests().count == 1)
    }

    @Test func cloudRewriteSkipsManualPunctuationCleanup() async throws {
        let audioFileURL = makeAudioFileURL()
        defer { try? FileManager.default.removeItem(at: audioFileURL) }

        let direct = TestTranscriptionService(result: "raw transcript")
        let rewrite = RecordingRewriteService()
        await rewrite.setResult("云端模型已经处理好这个句号。")
        let (store, _, _) = try makeSettingsStore(
            transcriptionProvider: .openAI,
            rewriteProvider: .openAI,
            rewriteEnabled: true,
            openAIAPIKey: "sk-test"
        )

        let service = makeDictationService(
            settingsStore: store,
            directTranscriptionService: direct,
            rewriteService: rewrite
        )

        try await service.startRecording()
        let result = try await service.stopRecording()

        #expect(result == "云端模型已经处理好这个句号。")
    }

    @Test func appleIntelligenceRewriteKeepsManualPunctuationCleanup() async throws {
        let audioFileURL = makeAudioFileURL()
        defer { try? FileManager.default.removeItem(at: audioFileURL) }

        let direct = TestTranscriptionService(result: "raw transcript")
        let rewrite = RecordingRewriteService()
        await rewrite.setResult("Apple Intelligence 仍然需要这层清理。")
        let (store, _, _) = try makeSettingsStore(
            transcriptionProvider: .openAI,
            rewriteProvider: .appleIntelligence,
            rewriteEnabled: true,
            openAIAPIKey: "sk-test"
        )

        let service = makeDictationService(
            settingsStore: store,
            directTranscriptionService: direct,
            rewriteService: rewrite
        )

        try await service.startRecording()
        let result = try await service.stopRecording()

        #expect(result == "Apple Intelligence 仍然需要这层清理")
    }

    @Test func byokGroqToGroqUsesSingleProviderForBothRemoteSteps() async throws {
        let audioFileURL = makeAudioFileURL()
        defer { try? FileManager.default.removeItem(at: audioFileURL) }

        let direct = TestTranscriptionService(result: "groq transcript")
        let rewrite = RecordingRewriteService()
        await rewrite.setResult("groq rewrite")
        let (store, _, _) = try makeSettingsStore(
            transcriptionProvider: .groq,
            rewriteProvider: .groq,
            rewriteEnabled: true,
            groqAPIKey: "gsk-test"
        )

        let service = makeDictationService(
            settingsStore: store,
            directTranscriptionService: direct,
            rewriteService: rewrite
        )

        try await service.startRecording()
        let result = try await service.stopRecording()
        let request = try #require(await rewrite.recordedRequests().first)

        #expect(result == "groq rewrite")
        #expect(request.text == "groq transcript")
        #expect(await direct.callCount() == 1)
    }

    @Test func byokGroqToOpenAIUsesIntermediateTranscriptOnlyForRewrite() async throws {
        let audioFileURL = makeAudioFileURL()
        defer { try? FileManager.default.removeItem(at: audioFileURL) }

        let direct = TestTranscriptionService(result: "mixed provider transcript")
        let rewrite = RecordingRewriteService()
        await rewrite.setResult("mixed provider rewrite")
        let (store, _, _) = try makeSettingsStore(
            transcriptionProvider: .groq,
            rewriteProvider: .openAI,
            rewriteEnabled: true,
            openAIAPIKey: "sk-test",
            groqAPIKey: "gsk-test"
        )

        let service = makeDictationService(
            settingsStore: store,
            directTranscriptionService: direct,
            rewriteService: rewrite
        )

        try await service.startRecording()
        let result = try await service.stopRecording()
        let request = try #require(await rewrite.recordedRequests().first)

        #expect(result == "mixed provider rewrite")
        #expect(request.text == "mixed provider transcript")
        #expect(request.audience == .ai)
        #expect(await direct.callCount() == 1)
    }

    @Test func stopRecordingUsesProcessedAudioURLForTranscription() async throws {
        let sourceAudioURL = makeAudioFileURL()
        let processedAudioURL = makeAudioFileURL()
        defer { try? FileManager.default.removeItem(at: sourceAudioURL) }
        defer { try? FileManager.default.removeItem(at: processedAudioURL) }

        let direct = TestTranscriptionService(result: "processed transcript")
        let rewrite = RecordingRewriteService()
        await rewrite.setResult("processed transcript")
        let (store, _, _) = try makeSettingsStore()
        let postProcessor = TestAudioPostProcessor(
            result: makeProcessedAudioResult(
                processedURL: processedAudioURL,
                sourceURL: sourceAudioURL
            )
        )
        let capture = TestAudioCaptureService(audioFileURL: sourceAudioURL)

        let service = ConfigurableSpeechService(
            settingsStore: store,
            pipelineFactory: DictationPipelineFactory(
                makeLocalTranscriptionService: { direct },
                makeRewriteService: { _, _ in rewrite }
            ),
            audioPostProcessor: postProcessor,
            captureService: capture
        )

        try await service.startRecording()
        let transcript = try await service.stopRecording()

        let postProcessorInvocation = await postProcessor.lastInvocation()
        let directInvocation = await direct.lastInvocation()

        #expect(transcript == "processed transcript")
        #expect(postProcessorInvocation?.sourceURL == sourceAudioURL)
        #expect(postProcessorInvocation?.duration == 1.2)
        #expect(directInvocation?.fileURL == processedAudioURL)
        #expect(directInvocation?.duration == 1.2)
        #expect(await direct.callCount() == 1)
    }

    @Test func processedTemporaryFilesAreRemovedAfterSuccessfulTranscription() async throws {
        let sourceAudioURL = makeAudioFileURL()
        let processedAudioURL = makeAudioFileURL()
        defer { try? FileManager.default.removeItem(at: sourceAudioURL) }

        let direct = TestTranscriptionService(result: "processed transcript")
        let rewrite = RecordingRewriteService()
        let (store, _, _) = try makeSettingsStore()
        let postProcessor = TestAudioPostProcessor(
            result: makeProcessedAudioResult(
                processedURL: processedAudioURL,
                sourceURL: sourceAudioURL
            )
        )
        let capture = TestAudioCaptureService(audioFileURL: sourceAudioURL)

        let service = ConfigurableSpeechService(
            settingsStore: store,
            pipelineFactory: DictationPipelineFactory(
                makeLocalTranscriptionService: { direct },
                makeRewriteService: { _, _ in rewrite }
            ),
            audioPostProcessor: postProcessor,
            captureService: capture
        )

        try await service.startRecording()
        _ = try await service.stopRecording()

        #expect(!FileManager.default.fileExists(atPath: processedAudioURL.path))
    }

    @Test func processedTemporaryFilesAreRemovedAfterTranscriptionFailure() async throws {
        let sourceAudioURL = makeAudioFileURL()
        let processedAudioURL = makeAudioFileURL()
        defer { try? FileManager.default.removeItem(at: sourceAudioURL) }

        let direct = TestTranscriptionService(outcome: .failure(TestError.expected))
        let rewrite = RecordingRewriteService()
        let (store, _, _) = try makeSettingsStore()
        let postProcessor = TestAudioPostProcessor(
            result: makeProcessedAudioResult(
                processedURL: processedAudioURL,
                sourceURL: sourceAudioURL
            )
        )
        let capture = TestAudioCaptureService(audioFileURL: sourceAudioURL)

        let service = ConfigurableSpeechService(
            settingsStore: store,
            pipelineFactory: DictationPipelineFactory(
                makeLocalTranscriptionService: { direct },
                makeRewriteService: { _, _ in rewrite }
            ),
            audioPostProcessor: postProcessor,
            captureService: capture
        )

        try await service.startRecording()

        await #expect(throws: TestError.expected) {
            try await service.stopRecording()
        }

        #expect(!FileManager.default.fileExists(atPath: processedAudioURL.path))
        #expect(await direct.callCount() == 1)
        #expect(await rewrite.recordedRequests().isEmpty)
    }

    @Test func processedTemporaryFilesAreRemovedAfterRewriteFailure() async throws {
        let sourceAudioURL = makeAudioFileURL()
        let processedAudioURL = makeAudioFileURL()
        defer { try? FileManager.default.removeItem(at: sourceAudioURL) }

        let direct = TestTranscriptionService(result: "processed transcript")
        let rewrite = RecordingRewriteService()
        await rewrite.setError(TestError.expected)
        let (store, _, _) = try makeSettingsStore(rewriteEnabled: true)
        let postProcessor = TestAudioPostProcessor(
            result: makeProcessedAudioResult(
                processedURL: processedAudioURL,
                sourceURL: sourceAudioURL
            )
        )
        let capture = TestAudioCaptureService(audioFileURL: sourceAudioURL)

        let service = ConfigurableSpeechService(
            settingsStore: store,
            pipelineFactory: DictationPipelineFactory(
                makeLocalTranscriptionService: { direct },
                makeRewriteService: { _, _ in rewrite }
            ),
            audioPostProcessor: postProcessor,
            captureService: capture
        )

        try await service.startRecording()

        let result = try await service.stopRecording()

        #expect(result == "processed transcript")
        #expect(!FileManager.default.fileExists(atPath: processedAudioURL.path))
        #expect(await direct.callCount() == 1)
        #expect(await rewrite.recordedRequests().count == 1)
    }

    @Test func primaryChineseLanguagePassesLanguageBiasToRewrite() async throws {
        let audioFileURL = makeAudioFileURL()
        defer { try? FileManager.default.removeItem(at: audioFileURL) }

        let direct = TestTranscriptionService(result: "Today we are reviewing this PR")
        let rewrite = RecordingRewriteService()
        let (store, _, _) = try makeSettingsStore(
            rewriteEnabled: true,
            transcriptionPrimaryLanguage: "zh"
        )
        let capture = TestAudioCaptureService(audioFileURL: audioFileURL)

        let service = ConfigurableSpeechService(
            settingsStore: store,
            pipelineFactory: DictationPipelineFactory(
                makeLocalTranscriptionService: { direct },
                makeRewriteService: { _, _ in rewrite }
            ),
            captureService: capture
        )

        try await service.startRecording()
        _ = try await service.stopRecording()

        let directInvocation = await direct.lastInvocation()
        let rewriteRequests = await rewrite.recordedRequests()

        #expect(directInvocation?.languageCode == "zh")
        #expect(rewriteRequests.first?.languageCode == "zh")
    }

    @Test func emptyTranscriptThrowsEmptyTranscription() async throws {
        let audioFileURL = makeAudioFileURL()
        let direct = TestTranscriptionService(result: "")
        let rewrite = RecordingRewriteService()
        let (store, _, _) = try makeSettingsStore()
        let capture = TestAudioCaptureService(audioFileURL: audioFileURL)
        let service = ConfigurableSpeechService(
            settingsStore: store,
            pipelineFactory: DictationPipelineFactory(
                makeLocalTranscriptionService: { direct },
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
        let rewrite = RecordingRewriteService()
        let (store, _, _) = try makeSettingsStore()
        let capture = TestAudioCaptureService(audioFileURL: audioFileURL, audioDurationSeconds: 1)
        let service = ConfigurableSpeechService(
            settingsStore: store,
            pipelineFactory: DictationPipelineFactory(
                makeLocalTranscriptionService: { direct },
                makeRewriteService: { _, _ in rewrite }
            ),
            captureService: capture
        )

        try await service.startRecording()
        await #expect(throws: SpeechServiceError.emptyTranscription) {
            try await service.stopRecording()
        }

        #expect(await direct.callCount() == 0)
        #expect(await rewrite.recordedRequests().isEmpty)
    }

    @Test func rewriteFailureThrows() async throws {
        let audioFileURL = makeAudioFileURL()
        let direct = TestTranscriptionService(result: "source")
        let rewrite = RecordingRewriteService()
        await rewrite.setError(TestError.expected)
        let (store, _, _) = try makeSettingsStore(rewriteEnabled: true)
        let capture = TestAudioCaptureService(audioFileURL: audioFileURL)

        let service = ConfigurableSpeechService(
            settingsStore: store,
            pipelineFactory: DictationPipelineFactory(
                makeLocalTranscriptionService: { direct },
                makeRewriteService: { _, _ in rewrite }
            ),
            captureService: capture
        )

        try await service.startRecording()
        defer { try? FileManager.default.removeItem(at: audioFileURL) }

        let result = try await service.stopRecording()

        #expect(result == "source")
        #expect(await direct.callCount() == 1)
        #expect(await rewrite.recordedRequests().count == 1)
    }

    @Test func transcriptionFailurePropagatesAndCannotRetryLocally() async throws {
        let audioFileURL = makeAudioFileURL()
        let direct = TestTranscriptionService(outcome: .failure(TestError.expected))
        let rewrite = RecordingRewriteService()
        let (store, _, _) = try makeSettingsStore()
        let capture = TestAudioCaptureService(audioFileURL: audioFileURL)
        let service = ConfigurableSpeechService(
            settingsStore: store,
            pipelineFactory: DictationPipelineFactory(
                makeLocalTranscriptionService: { direct },
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
        #expect(await rewrite.recordedRequests().isEmpty)
    }

    @Test func transcriptionFailurePreventsRewriteStepFromStarting() async throws {
        let audioFileURL = makeAudioFileURL()
        defer { try? FileManager.default.removeItem(at: audioFileURL) }

        let direct = TestTranscriptionService(outcome: .failure(TestError.expected))
        let rewrite = RecordingRewriteService()
        let (store, _, _) = try makeSettingsStore(
            rewriteEnabled: true
        )

        let service = makeDictationService(
            settingsStore: store,
            directTranscriptionService: direct,
            rewriteService: rewrite
        )

        try await service.startRecording()

        await #expect(throws: TestError.expected) {
            try await service.stopRecording()
        }

        #expect(await rewrite.recordedRequests().isEmpty)
    }

    @Test func dictationTranscriptComparisonKeepsRawAndRewrittenTextTogether() {
        let comparison = DictationTranscriptComparison(
            provider: .appleIntelligence,
            outcome: .rewritten,
            rawTranscript: "hello wrld",
            finalTranscript: "hello world",
            languageCode: "en"
        )

        #expect(comparison.provider == DictationProvider.appleIntelligence.rawValue)
        #expect(comparison.rawTranscript == "hello wrld")
        #expect(comparison.finalTranscript == "hello world")
        #expect(comparison.languageCode == "en")
        #expect(comparison.changed)
    }

    @Test func dictationTranscriptComparisonMarksUnchangedFallback() {
        let comparison = DictationTranscriptComparison(
            provider: .appleIntelligence,
            outcome: .fallbackAfterRewriteFailure,
            rawTranscript: "already clean",
            finalTranscript: "already clean",
            languageCode: "zh",
            errorDescription: "rewrite failed"
        )

        #expect(comparison.changed == false)
        #expect(comparison.languageCode == "zh")
        #expect(comparison.errorDescription == "rewrite failed")
        #expect(comparison.rawTranscript == comparison.finalTranscript)
    }

    @Test func appleIntelligenceTranslationGuardDetectsMixedEnglishTranslatedIntoChinese() {
        #expect(
            ConfigurableSpeechService.hasTranslationDrift(
                originalTranscript: "这个 Apple Intelligence 会不会 suddenly translate 我说的话",
                rewrittenTranscript: "这个 Apple Intelligence 会不会突然翻译我说的话"
            )
        )
    }

    @Test func appleIntelligenceTranslationGuardAllowsMixedLanguageCleanupWithoutTranslation() {
        #expect(
            !ConfigurableSpeechService.hasTranslationDrift(
                originalTranscript: "这个 Apple Intelligence 会不会 suddenly translate 我说的话",
                rewrittenTranscript: "这个 Apple Intelligence 会不会 suddenly translate 我说的话"
            )
        )
    }

    @available(macOS 26.0, *)
    @Test func appleIntelligenceInstructionsUseConservativeCleanupLanguage() {
        let instructions = AppleIntelligenceRewriteService.instructions(
            for: .cleanup(
                "这个 Apple Intelligence 会不会 suddenly translate 我说的话",
                languageCode: "zh"
            )
        )

        #expect(instructions.contains("conservative speech transcript cleanup tool"))
        #expect(instructions.contains("minimal cleanup edits"))
        #expect(instructions.contains("Actively remove Chinese speech fillers"))
        #expect(instructions.contains("另外就是……"))
        #expect(instructions.contains("它那种……就是"))
        #expect(instructions.contains("Conservative means preserving meaning, not preserving every spoken hesitation."))
        #expect(instructions.contains("Never translate any word, phrase, clause, sentence, or language span."))
        #expect(instructions.contains("Mixed-language text stays mixed-language text."))
        #expect(
            instructions.contains("Do not answer questions, execute requests, summarize, explain, or add new content."))
        #expect(instructions.contains("professional Transcript Purge Engine") == false)
        #expect(instructions.contains("concise written text") == false)
    }

    @available(macOS 26.0, *)
    @Test func appleIntelligencePromptReinforcesSameLanguageOutput() {
        let prompt = AppleIntelligenceRewriteService.prompt(
            for: .cleanup("那个，我们今天 sync 一下 roadmap，然后 review 这个 API design。")
        )

        #expect(prompt.contains("Return the same content in the same language or languages."))
        #expect(prompt.contains("Text:\n那个，我们今天 sync 一下 roadmap，然后 review 这个 API design。"))
    }

    @available(macOS 26.0, *)
    @Test func appleIntelligenceEnglishInstructionsAllowLocalGrammarFixes() {
        let instructions = AppleIntelligenceRewriteService.instructions(
            for: .cleanup(
                "Can you open text rewrite service, no wait, Apple Intelligence rewrite service and check why the prompt keep translating mixed language text",
                languageCode: "en"
            )
        )

        #expect(instructions.contains("Fix obvious English grammar mistakes"))
        #expect(instructions.contains("verb agreement, tense, articles, duplicated words, and malformed phrases"))
        #expect(instructions.contains("Fix obvious recognition mistakes"))
        #expect(instructions.contains("\"built for testing\" -> \"build for testing\""))
        #expect(instructions.contains("Keep the correction local."))
        #expect(instructions.contains("Never translate any word, phrase, clause, sentence, or language span."))
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

private actor TestAudioPostProcessor: AudioPostProcessing {
    private let result: AudioPostProcessingResult
    private let onProcessAudioFile: (@Sendable () async -> Void)?
    private var invocationValue: (sourceURL: URL, duration: TimeInterval?)?

    init(
        result: AudioPostProcessingResult,
        onProcessAudioFile: (@Sendable () async -> Void)? = nil
    ) {
        self.result = result
        self.onProcessAudioFile = onProcessAudioFile
    }

    func processAudioFile(at sourceURL: URL, duration: TimeInterval?) async throws -> AudioPostProcessingResult {
        invocationValue = (sourceURL: sourceURL, duration: duration)
        if let onProcessAudioFile {
            await onProcessAudioFile()
        }
        return result
    }

    func lastInvocation() -> (sourceURL: URL, duration: TimeInterval?)? {
        invocationValue
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
    private var lastInvocationValue: (fileURL: URL, languageCode: String?, prompt: String?, duration: TimeInterval?)?

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
    ) async throws -> TranscriptionResult {
        callCountValue += 1
        lastInvocationValue = (
            fileURL: fileURL, languageCode: languageCode, prompt: prompt, duration: audioDurationSeconds
        )
        #expect(!fileURL.path.isEmpty)

        switch outcome {
        case .success(let value):
            return TranscriptionResult(text: value, languageCode: languageCode)
        case .failure(let error):
            throw error
        }
    }

    func callCount() -> Int {
        callCountValue
    }

    func lastInvocation() -> (fileURL: URL, languageCode: String?, prompt: String?, duration: TimeInterval?)? {
        lastInvocationValue
    }
}
