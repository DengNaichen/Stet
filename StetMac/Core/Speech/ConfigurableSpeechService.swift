import Foundation
import StetRewrite
import StetCore
import os
#if os(macOS)
    import StetVisuals
#endif

actor ConfigurableSpeechService: SpeechService, AudioLevelSource {
    private let settingsStore: DictationSettingsStore
    private let locale: Locale
    private let pipelineFactory: DictationPipelineFactory
    private let audienceProvider: @Sendable () -> AppAudience
    private let captureServiceFactory: @Sendable () -> any AudioCaptureService
    private let audioPostProcessor: any AudioPostProcessing
    private let beginActiveCapture: (@Sendable () async -> Void)?
    private let resumePassiveCapture: (@Sendable () async -> Void)?
    private let audioLevelBridge = AudioLevelBridge()
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.openwhispr.Stet", category: "SpeechService")
    #if os(macOS)
        private let audioFeatureBridge = AudioFeatureBridge()
    #endif

    private var activePipeline: DictationPipeline?
    private var activeCaptureService: (any AudioCaptureService)?
    private var audioLevelTask: Task<Void, Never>?
    private var transcriptionPrewarmTask: Task<Void, Never>?
    private var rewritePrewarmTask: Task<Void, Never>?
    #if os(macOS)
        private var audioFeatureTask: Task<Void, Never>?
    #endif
    private var reusableCaptureService: (any AudioCaptureService)?
    private var ownsActiveCapture = false

    init(
        settingsStore: DictationSettingsStore = DictationSettingsStore(),
        locale: Locale = .autoupdatingCurrent,
        pipelineFactory: DictationPipelineFactory,
        audienceProvider: (@Sendable () -> AppAudience)? = nil,
        audioPostProcessor: (any AudioPostProcessing)? = nil,
        captureService: (any AudioCaptureService)? = nil,
        captureServiceFactory: (@Sendable () -> any AudioCaptureService)? = nil,
        beginActiveCapture: (@Sendable () async -> Void)? = nil,
        resumePassiveCapture: (@Sendable () async -> Void)? = nil
    ) {
        precondition(
            captureService == nil || captureServiceFactory == nil,
            "Provide either a capture service or a capture service factory."
        )

        self.settingsStore = settingsStore
        self.locale = locale
        self.pipelineFactory = pipelineFactory
        self.audienceProvider =
            audienceProvider ?? {
                AppBranchMonitor.shared.currentApp?.audience ?? .ai
            }
        self.audioPostProcessor = audioPostProcessor ?? DefaultAudioPostProcessor()
        self.beginActiveCapture = beginActiveCapture
        self.resumePassiveCapture = resumePassiveCapture
        if let captureService {
            self.captureServiceFactory = { captureService }
            self.reusableCaptureService = captureService
        } else if let captureServiceFactory {
            self.captureServiceFactory = captureServiceFactory
        } else {
            let defaultCaptureService = MacAudioCaptureService()
            self.captureServiceFactory = { defaultCaptureService }
            self.reusableCaptureService = defaultCaptureService
        }
    }

    func makeAudioLevelStream() async -> AsyncStream<Double> {
        audioLevelBridge.makeStream()
    }

    #if os(macOS)
        func makeAudioFeatureStream() async -> AsyncStream<MacDictationCapsuleVisualSignals> {
            audioFeatureBridge.makeStream()
        }
    #endif

    func startRecording() async throws {
        try await startRecording(activateRecordingWindow: false)
    }

    func startRecordingAndActivate() async throws {
        try await startRecording(activateRecordingWindow: true)
    }

    private func startRecording(activateRecordingWindow: Bool) async throws {
        guard activePipeline == nil else {
            throw SpeechServiceError.alreadyRecording
        }

        if let beginActiveCapture {
            await beginActiveCapture()
            ownsActiveCapture = true
        }
        let snapshot = settingsStore.loadSnapshot()
        let pipelineStartedAt = ProcessInfo.processInfo.systemUptime
        let pipeline: DictationPipeline
        do {
            pipeline = try await pipelineFactory.makePipeline(from: snapshot)
        } catch {
            await resumePassiveCaptureIfNeeded()
            throw error
        }
        activePipeline = pipeline
        let pipelineFactoryMs = Self.elapsedMilliseconds(since: pipelineStartedAt)
        Self.logStartupTiming("pipelineFactoryMs=\(Self.formatMilliseconds(pipelineFactoryMs))")
        await DictationStartupProbe.shared.record(
            .pipelineReady,
            note: "pipelineFactoryMs=\(Self.formatMilliseconds(pipelineFactoryMs))"
        )
        let captureService: any AudioCaptureService
        if let reusableCaptureService {
            captureService = reusableCaptureService
        } else {
            let newCaptureService = captureServiceFactory()
            reusableCaptureService = newCaptureService
            captureService = newCaptureService
        }
        activeCaptureService = captureService

        do {
            let captureServiceStartedAt = ProcessInfo.processInfo.systemUptime
            try await captureService.startRecording()
            let captureServiceStartMs = Self.elapsedMilliseconds(since: captureServiceStartedAt)
            Self.logStartupTiming("captureServiceStartMs=\(Self.formatMilliseconds(captureServiceStartMs))")

            if activateRecordingWindow {
                let captureWindowStartedAt = ProcessInfo.processInfo.systemUptime
                try await captureService.activateRecordingWindow()
                let captureWindowActivationMs = Self.elapsedMilliseconds(since: captureWindowStartedAt)
                Self.logStartupTiming("captureWindowActivationMs=\(Self.formatMilliseconds(captureWindowActivationMs))")
            }

            await startAudioLevelForwarding(using: captureService)
            #if os(macOS)
                await startAudioFeatureForwarding(using: captureService)
            #endif
            startTranscriptionPrewarm(using: pipeline)
            startRewritePrewarm(using: pipeline)
        } catch is CancellationError {
            activePipeline = nil
            activeCaptureService = nil
            stopTranscriptionPrewarm()
            stopRewritePrewarm()
            stopAudioLevelForwarding()
            #if os(macOS)
                stopAudioFeatureForwarding()
            #endif
            await DictationStartupProbe.shared.record(.cancelled)
            await resumePassiveCaptureIfNeeded()
            throw CancellationError()
        } catch {
            activePipeline = nil
            activeCaptureService = nil
            stopTranscriptionPrewarm()
            stopRewritePrewarm()
            stopAudioLevelForwarding()
            #if os(macOS)
                stopAudioFeatureForwarding()
            #endif
            await DictationStartupProbe.shared.record(.failed, note: error.localizedDescription)
            await resumePassiveCaptureIfNeeded()
            throw error
        }
    }

    func activateRecordingWindow() async throws {
        guard let captureService = activeCaptureService else {
            throw SpeechServiceError.notRecording
        }

        try await captureService.activateRecordingWindow()
    }

    func stopRecording(
        onCaptureStopped: (@Sendable () async -> Void)? = nil
    ) async throws -> String {
        guard let pipeline = activePipeline,
            let captureService = activeCaptureService
        else {
            throw SpeechServiceError.notRecording
        }

        defer {
            self.activePipeline = nil
            self.activeCaptureService = nil
            stopTranscriptionPrewarm()
            stopRewritePrewarm()
            stopAudioLevelForwarding()
            #if os(macOS)
                stopAudioFeatureForwarding()
            #endif
        }

        let releaseContextOnExit: @Sendable () async -> Void = {
            #if os(macOS)
                await LocalWhisperContextManager.shared.cleanupResources()
                await LocalParakeetContextManager.shared.cleanupResources()
                await FunASRNanoContextManager.shared.cleanupResources()
            #endif
        }

        let captureResult: (url: URL, duration: TimeInterval?)
        do {
            captureResult = try await captureService.stopRecording()
        } catch {
            await resumePassiveCaptureIfNeeded()
            throw error
        }
        await resumePassiveCaptureIfNeeded()
        if let onCaptureStopped {
            await onCaptureStopped()
        }
        let processedCaptureResult =
            if settingsStore.loadSnapshot().transcriptionEngine == .funASRNano {
                AudioPostProcessingResult.passthrough(
                    url: captureResult.url,
                    duration: captureResult.duration
                )
            } else {
                try await audioPostProcessor.processAudioFile(
                    at: captureResult.url,
                    duration: captureResult.duration
                )
            }

        defer {
            let cleanupURLs = Set(processedCaptureResult.cleanupURLs)
            for url in cleanupURLs {
                try? FileManager.default.removeItem(at: url)
            }
        }

        guard !processedCaptureResult.shouldDiscardAsNoSpeech else {
            logger.info("Discarding dictation capture because no speech was detected locally.")
            await releaseContextOnExit()
            throw SpeechServiceError.emptyTranscription
        }

        await DictationLatencyProbe.shared.beginSession(audioDurationSeconds: processedCaptureResult.duration)
        let processingStartedAt = ProcessInfo.processInfo.systemUptime

        var transcriptionPrompt: String? = nil
        if let provider = pipeline.promptProvider {
            transcriptionPrompt = await provider()
        }

        logger.info("Submitting transcription request.")

        let intermediateTranscript: String
        let transcriptionStartedAt = ProcessInfo.processInfo.systemUptime
        let transcriptionResult: TranscriptionResult
        do {
            await waitForTranscriptionPrewarm()
            await DictationLatencyProbe.shared.record(.transcriptionStarted)
            transcriptionResult = try await pipeline.transcriptionService.transcribe(
                audioFileAt: processedCaptureResult.url,
                languageCode: pipeline.transcriptionLanguageCode,
                prompt: transcriptionPrompt,
                audioDurationSeconds: processedCaptureResult.duration
            )
            let trimmedTranscript = transcriptionResult.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedTranscript.isEmpty else {
                throw SpeechServiceError.emptyTranscription
            }
            intermediateTranscript = trimmedTranscript
            let transcriptionStageMs = Self.elapsedMilliseconds(since: transcriptionStartedAt)
            logger.info(
                "DictationStage transcriptionMs=\(Self.formatMilliseconds(transcriptionStageMs)) audioDurationSeconds=\(Self.formatDurationSeconds(processedCaptureResult.duration)) transcriptChars=\(trimmedTranscript.count) rewriteEnabled=\(pipeline.rewriteService != nil) detectedLanguage=\(transcriptionResult.languageCode ?? "unknown")"
            )
        } catch {
            await DictationLatencyProbe.shared.record(.transcriptionFailed, note: error.localizedDescription)
            logger.error("Transcription failed: \(error.localizedDescription)")
            await releaseContextOnExit()
            throw error
        }

        do {
            let finalTranscript: String
            let rewriteStartedAt = ProcessInfo.processInfo.systemUptime
            do {
                if let rewriteService = pipeline.rewriteService {
                    let rewriteAudience = pipeline.usesAudienceAwareLocalPrompts ? audienceProvider() : nil
                    let appName = AppBranchMonitor.shared.currentApp?.localizedName
                    let request = TextRewriteRequest.cleanup(
                        intermediateTranscript,
                        audience: rewriteAudience,
                        preferredSpellings: pipeline.preferredSpellings,
                        languageCode: transcriptionResult.languageCode ?? pipeline.transcriptionLanguageCode,
                        appName: appName
                    )
                    let rewrittenTranscript = try await rewriteService.rewrite(request)

                    finalTranscript = rewrittenTranscript
                    if let rewriteProvider = pipeline.rewriteProvider {
                        await DictationTranscriptTrace.shared.record(
                            provider: rewriteProvider,
                            outcome: .rewritten,
                            rawTranscript: intermediateTranscript,
                            finalTranscript: finalTranscript,
                            languageCode: request.languageCode
                        )
                    }
                    let rewriteStageMs = Self.elapsedMilliseconds(since: rewriteStartedAt)
                } else {
                    finalTranscript = intermediateTranscript
                    logger.info(
                        "DictationStage rewriteSkipped inputChars=\(intermediateTranscript.count)"
                    )
                }
            } catch {
                logger.error("Rewrite failed: \(error.localizedDescription). Falling back to raw transcript.")
                if let rewriteProvider = pipeline.rewriteProvider {
                    await DictationTranscriptTrace.shared.record(
                        provider: rewriteProvider,
                        outcome: .fallbackAfterRewriteFailure,
                        rawTranscript: intermediateTranscript,
                        finalTranscript: intermediateTranscript,
                        languageCode: transcriptionResult.languageCode ?? pipeline.transcriptionLanguageCode,
                        errorDescription: error.localizedDescription
                    )
                }
                finalTranscript = intermediateTranscript
            }

            let trimmedFinalTranscript = finalTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedTranscript: String
            if Self.shouldApplyManualPunctuationCleanup(rewriteProvider: pipeline.rewriteProvider) {
                let normalizedTranscript = PunctuationNormalizer.normalize(
                    trimmedFinalTranscript,
                    languageCode: transcriptionResult.languageCode ?? pipeline.transcriptionLanguageCode
                )
                trimmedTranscript = Self.stripTrailingPeriod(normalizedTranscript)
            } else {
                trimmedTranscript = trimmedFinalTranscript
            }
            guard !trimmedTranscript.isEmpty else {
                await releaseContextOnExit()
                throw SpeechServiceError.emptyTranscription
            }

            let totalProcessingMs = Self.elapsedMilliseconds(since: processingStartedAt)
            logger.info(
                "DictationSummary totalProcessingMs=\(Self.formatMilliseconds(totalProcessingMs)) audioDurationSeconds=\(Self.formatDurationSeconds(processedCaptureResult.duration)) finalTextChars=\(trimmedTranscript.count) rewriteEnabled=\(pipeline.rewriteService != nil)"
            )

            await releaseContextOnExit()
            return trimmedTranscript
        } catch {
            await DictationLatencyProbe.shared.record(.transcriptionFailed, note: error.localizedDescription)
            logger.error("Post-transcription processing failed: \(error.localizedDescription)")
            await releaseContextOnExit()
            throw error
        }
    }

    func cancelRecording() async {
        guard activePipeline != nil else { return }
        self.activePipeline = nil
        stopTranscriptionPrewarm()
        stopRewritePrewarm()
        let captureService = activeCaptureService
        activeCaptureService = nil
        stopAudioLevelForwarding()
        #if os(macOS)
            stopAudioFeatureForwarding()
        #endif
        if let captureService {
            await captureService.cancelRecording()
        }
        await resumePassiveCaptureIfNeeded()
        // Match VoiceInk's cleanupResources() in the cancel branch of toggleRecord:
        // a prewarm task may have loaded the model already, so release it here too.
        #if os(macOS)
            await LocalWhisperContextManager.shared.cleanupResources()
            await LocalParakeetContextManager.shared.cleanupResources()
            await FunASRNanoContextManager.shared.cleanupResources()
        #endif
    }

    private func resumePassiveCaptureIfNeeded() async {
        guard ownsActiveCapture else { return }
        ownsActiveCapture = false
        await resumePassiveCapture?()
    }

    func prewarm() async {
        let captureService: any AudioCaptureService
        if let reusableCaptureService {
            captureService = reusableCaptureService
        } else {
            let newCaptureService = captureServiceFactory()
            reusableCaptureService = newCaptureService
            captureService = newCaptureService
        }

        await captureService.prewarm()
    }

    private func startTranscriptionPrewarm(using pipeline: DictationPipeline) {
        transcriptionPrewarmTask?.cancel()
        transcriptionPrewarmTask = Task(priority: .userInitiated) {
            // Delay pre-warm by 1s to allow UI animations to settle after button press
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }

            let prewarmStartedAt = ProcessInfo.processInfo.systemUptime
            do {
                try await pipeline.transcriptionService.prewarm()
                let prewarmMs = Self.elapsedMilliseconds(since: prewarmStartedAt)
                logger.info(
                    "DictationStage transcriptionPrewarmMs=\(Self.formatMilliseconds(prewarmMs))"
                )
            } catch is CancellationError {
            } catch {
                logger.warning(
                    "Local transcription prewarm failed during recording. error=\(error.localizedDescription)")
            }
        }
    }

    private func startRewritePrewarm(using pipeline: DictationPipeline) {
        rewritePrewarmTask?.cancel()
        guard let rewriteService = pipeline.rewriteService else {
            rewritePrewarmTask = nil
            return
        }

        let rewriteAudience = pipeline.usesAudienceAwareLocalPrompts ? audienceProvider() : nil
        rewritePrewarmTask = Task(priority: .utility) {
            // Delay pre-warm by 1s to allow UI animations to settle after button press
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }

            await rewriteService.prewarm(
                .cleanup(
                    "",
                    audience: rewriteAudience,
                    preferredSpellings: pipeline.preferredSpellings,
                )
            )
        }
    }

    private func waitForTranscriptionPrewarm() async {
        guard let transcriptionPrewarmTask else { return }
        let waitStartedAt = ProcessInfo.processInfo.systemUptime
        _ = await transcriptionPrewarmTask.result
        let waitMs = Self.elapsedMilliseconds(since: waitStartedAt)
        logger.info(
            "DictationStage transcriptionPrewarmWaitMs=\(Self.formatMilliseconds(waitMs))"
        )
        if self.transcriptionPrewarmTask == transcriptionPrewarmTask {
            self.transcriptionPrewarmTask = nil
        }
    }

    private func stopTranscriptionPrewarm() {
        transcriptionPrewarmTask?.cancel()
        transcriptionPrewarmTask = nil
    }

    private func stopRewritePrewarm() {
        rewritePrewarmTask?.cancel()
        rewritePrewarmTask = nil
    }

    private func startAudioLevelForwarding(using captureService: any AudioCaptureService) async {
        audioLevelTask?.cancel()
        audioLevelTask = nil

        guard let streamingService = captureService as? any AudioLevelSource else { return }
        let audioLevelBridge = self.audioLevelBridge
        let stream = await streamingService.makeAudioLevelStream()

        audioLevelTask = Task {
            for await level in stream {
                if Task.isCancelled {
                    break
                }

                audioLevelBridge.emit(level)
            }
        }
    }

    private func stopAudioLevelForwarding() {
        audioLevelTask?.cancel()
        audioLevelTask = nil
        // Do not finish the bridge here. The same speech service instance is
        // reused for the next capture, and closing the stream makes later UI
        // sessions look dead even when audio is flowing again.
        audioLevelBridge.emit(0)
    }

    #if os(macOS)
        private func startAudioFeatureForwarding(using captureService: any AudioCaptureService) async {
            audioFeatureTask?.cancel()
            audioFeatureTask = nil

            guard let streamingService = captureService as? any AudioFeatureSource else { return }
            let audioFeatureBridge = self.audioFeatureBridge
            let stream = await streamingService.makeAudioFeatureStream()

            audioFeatureTask = Task {
                for await features in stream {
                    if Task.isCancelled {
                        break
                    }

                    audioFeatureBridge.emit(features)
                }
            }
        }

        private func stopAudioFeatureForwarding() {
            audioFeatureTask?.cancel()
            audioFeatureTask = nil
            audioFeatureBridge.emit(.zero)
        }
    #endif

    private nonisolated static func logStartupTiming(_ payload: String) {
        guard UserDefaults.standard.bool(forKey: MacPreferences.dictationPerfTracingEnabled) else {
            return
        }

        Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.openwhispr.Stet", category: "AudioStartup").info(
            "AudioStartup \(payload)")
    }

    private nonisolated static func elapsedMilliseconds(since start: TimeInterval) -> Double {
        (ProcessInfo.processInfo.systemUptime - start) * 1_000
    }

    private nonisolated static func formatMilliseconds(_ duration: Double) -> String {
        String(format: "%.1f", duration)
    }

    private nonisolated static func formatDurationSeconds(_ duration: TimeInterval?) -> String {
        guard let duration, duration.isFinite, duration >= 0 else {
            return "unknown"
        }

        return String(format: "%.3f", duration)
    }

    /// Strips a single trailing period (ASCII or CJK full stop) from the final
    /// transcript so that text pasted into AI tools does not end with an unwanted
    /// sentence-terminator the model may have added.
    private nonisolated static func stripTrailingPeriod(_ text: String) -> String {
        if text.hasSuffix("。") {
            return String(text.dropLast())
        }
        if text.hasSuffix(".") {
            return String(text.dropLast())
        }
        return text
    }

    private nonisolated static func shouldApplyManualPunctuationCleanup(
        rewriteProvider: DictationProvider?
    ) -> Bool {
        switch rewriteProvider {
        case .openAI, .groq, .deepSeek, .qwen, .glm, .doubao, .google, .anthropic, .custom:
            return false
        case .appleIntelligence, nil:
            return true
        }
    }

    /// Detects if the rewritten transcript has "drifted" from the original by
    /// translating mixed-language content instead of just cleaning it up.
    /// Used as a guardrail for Apple Intelligence rewrite.
    static func hasTranslationDrift(originalTranscript: String, rewrittenTranscript: String) -> Bool {
        let originalEnglishWords = extractEnglishWords(originalTranscript)
        let rewrittenEnglishWords = extractEnglishWords(rewrittenTranscript)

        let droppedWords = originalEnglishWords.subtracting(rewrittenEnglishWords)

        // If we dropped English words, it might be a translation.
        // We ignore very short words or common fillers if we wanted to be fancy,
        // but for a guardrail, any dropped English word in a mixed transcript is suspicious.
        return !droppedWords.isEmpty
    }

    private static func extractEnglishWords(_ text: String) -> Set<String> {
        let regex = try? NSRegularExpression(pattern: "[a-zA-Z]{2,}")
        let nsString = text as NSString
        let matches = regex?.matches(in: text, range: NSRange(location: 0, length: nsString.length)) ?? []
        return Set(matches.map { nsString.substring(with: $0.range).lowercased() })
    }

}

extension ConfigurableSpeechService {
    static func live(
        settingsStore: DictationSettingsStore = DictationSettingsStore(),
        captureService: MacAudioCaptureService? = nil,
        beginActiveCapture: (@Sendable () async -> Void)? = nil,
        resumePassiveCapture: (@Sendable () async -> Void)? = nil
    ) -> ConfigurableSpeechService {
        ConfigurableSpeechService(
            settingsStore: settingsStore,
            pipelineFactory: .live(),
            captureService: captureService,
            beginActiveCapture: beginActiveCapture,
            resumePassiveCapture: resumePassiveCapture
        )
    }
}

#if os(macOS)
    extension ConfigurableSpeechService: AudioFeatureSource {}
#endif
