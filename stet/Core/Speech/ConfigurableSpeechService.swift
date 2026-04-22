import Foundation
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
    private let audioLevelBridge = AudioLevelBridge()
    #if os(macOS)
        private let audioFeatureBridge = AudioFeatureBridge()
    #endif

    private var activePipeline: DictationPipeline?
    private var activeCaptureService: (any AudioCaptureService)?
    private var audioLevelTask: Task<Void, Never>?
    private var transcriptionPrewarmTask: Task<Void, Never>?
    #if os(macOS)
        private var audioFeatureTask: Task<Void, Never>?
    #endif
    private var reusableCaptureService: (any AudioCaptureService)?

    init(
        settingsStore: DictationSettingsStore = DictationSettingsStore(),
        locale: Locale = .autoupdatingCurrent,
        pipelineFactory: DictationPipelineFactory,
        audienceProvider: (@Sendable () -> AppAudience)? = nil,
        audioPostProcessor: (any AudioPostProcessing)? = nil,
        captureService: (any AudioCaptureService)? = nil,
        captureServiceFactory: (@Sendable () -> any AudioCaptureService)? = nil
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

        let snapshot = settingsStore.loadSnapshot()
        let pipelineStartedAt = ProcessInfo.processInfo.systemUptime
        // Resolve the execution route and validate provider requirements before
        // capture starts so BYOK configuration failures surface immediately.
        let pipeline = try await pipelineFactory.makePipeline(from: snapshot)
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
        } catch is CancellationError {
            activePipeline = nil
            activeCaptureService = nil
            stopTranscriptionPrewarm()
            stopAudioLevelForwarding()
            #if os(macOS)
                stopAudioFeatureForwarding()
            #endif
            await DictationStartupProbe.shared.record(.cancelled)
            throw CancellationError()
        } catch {
            activePipeline = nil
            activeCaptureService = nil
            stopTranscriptionPrewarm()
            stopAudioLevelForwarding()
            #if os(macOS)
                stopAudioFeatureForwarding()
            #endif
            await DictationStartupProbe.shared.record(.failed, note: error.localizedDescription)
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
            stopAudioLevelForwarding()
            #if os(macOS)
                stopAudioFeatureForwarding()
            #endif
        }

        let captureResult = try await captureService.stopRecording()
        if let onCaptureStopped {
            await onCaptureStopped()
        }
        let processedCaptureResult = try await audioPostProcessor.processAudioFile(
            at: captureResult.url,
            duration: captureResult.duration
        )

        defer {
            let cleanupURLs = Set(processedCaptureResult.cleanupURLs)
            for url in cleanupURLs {
                try? FileManager.default.removeItem(at: url)
            }
        }

        guard !processedCaptureResult.shouldDiscardAsNoSpeech else {
            AppLogger.info("Discarding dictation capture because no speech was detected locally.", category: .dictation)
            throw SpeechServiceError.emptyTranscription
        }

        await DictationLatencyProbe.shared.beginSession(audioDurationSeconds: processedCaptureResult.duration)
        let processingStartedAt = ProcessInfo.processInfo.systemUptime

        var transcriptionPrompt: String? = nil
        if let provider = pipeline.promptProvider {
            transcriptionPrompt = await provider()
        }

        AppLogger.info("Submitting transcription request.", category: .dictation)

        let intermediateTranscript: String
        let transcriptionStartedAt = ProcessInfo.processInfo.systemUptime
        do {
            await waitForTranscriptionPrewarm()
            let transcript = try await pipeline.transcriptionService.transcribe(
                audioFileAt: processedCaptureResult.url,
                languageCode: pipeline.transcriptionLanguageCode,
                prompt: transcriptionPrompt,
                audioDurationSeconds: processedCaptureResult.duration
            )
            let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedTranscript.isEmpty else {
                throw SpeechServiceError.emptyTranscription
            }
            intermediateTranscript = trimmedTranscript
            let transcriptionStageMs = Self.elapsedMilliseconds(since: transcriptionStartedAt)
            AppLogger.info(
                "DictationStage transcriptionMs=\(Self.formatMilliseconds(transcriptionStageMs)) audioDurationSeconds=\(Self.formatDurationSeconds(processedCaptureResult.duration)) transcriptChars=\(trimmedTranscript.count) rewriteEnabled=\(pipeline.rewriteService != nil)",
                category: .perfTrace
            )
        } catch {
            await DictationLatencyProbe.shared.record(.transcriptionFailed, note: error.localizedDescription)
            AppLogger.error("Transcription failed: \(error.localizedDescription)", category: .dictation)
            throw error
        }

        do {
            let finalTranscript: String
            let rewriteStartedAt = ProcessInfo.processInfo.systemUptime
            do {
                if let rewriteService = pipeline.rewriteService {
                    let rewriteAudience = pipeline.usesAudienceAwareLocalPrompts ? audienceProvider() : nil
                    finalTranscript = try await rewriteService.rewrite(
                        .cleanup(
                            intermediateTranscript,
                            audience: rewriteAudience,
                            preferredSpellings: pipeline.preferredSpellings,
                            additionalContext: pipeline.rewriteAdditionalContext
                        )
                    )
                    let rewriteStageMs = Self.elapsedMilliseconds(since: rewriteStartedAt)
                    AppLogger.info(
                        "DictationStage rewriteMs=\(Self.formatMilliseconds(rewriteStageMs)) inputChars=\(intermediateTranscript.count) audience=\(rewriteAudience?.rawValue ?? "none") preferredSpellingsCount=\(pipeline.preferredSpellings.count) additionalContextChars=\(pipeline.rewriteAdditionalContext?.count ?? 0)",
                        category: .perfTrace
                    )
                } else {
                    finalTranscript = intermediateTranscript
                    AppLogger.info(
                        "DictationStage rewriteSkipped inputChars=\(intermediateTranscript.count)",
                        category: .perfTrace
                    )
                }
            } catch {
                AppLogger.error(
                    "Rewrite failed: \(error.localizedDescription). Falling back to raw transcript.",
                    category: .dictation)
                finalTranscript = intermediateTranscript
            }

            let trimmedTranscript = Self.stripTrailingPeriod(
                finalTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            guard !trimmedTranscript.isEmpty else {
                throw SpeechServiceError.emptyTranscription
            }

            let totalProcessingMs = Self.elapsedMilliseconds(since: processingStartedAt)
            AppLogger.info(
                "DictationSummary totalProcessingMs=\(Self.formatMilliseconds(totalProcessingMs)) audioDurationSeconds=\(Self.formatDurationSeconds(processedCaptureResult.duration)) finalTextChars=\(trimmedTranscript.count) rewriteEnabled=\(pipeline.rewriteService != nil)",
                category: .perfTrace
            )

            return trimmedTranscript
        } catch {
            await DictationLatencyProbe.shared.record(.transcriptionFailed, note: error.localizedDescription)
            AppLogger.error("Post-transcription processing failed: \(error.localizedDescription)", category: .dictation)
            throw error
        }
    }

    func cancelRecording() async {
        guard activePipeline != nil else { return }
        self.activePipeline = nil
        stopTranscriptionPrewarm()
        let captureService = activeCaptureService
        activeCaptureService = nil
        stopAudioLevelForwarding()
        #if os(macOS)
            stopAudioFeatureForwarding()
        #endif
        if let captureService {
            await captureService.cancelRecording()
        }
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
        transcriptionPrewarmTask = Task(priority: .utility) {
            do {
                try await pipeline.transcriptionService.prewarm()
            } catch is CancellationError {
            } catch {
                AppLogger.warning(
                    "Local transcription prewarm failed during recording. error=\(error.localizedDescription)",
                    category: .dictation
                )
            }
        }
    }

    private func waitForTranscriptionPrewarm() async {
        guard let transcriptionPrewarmTask else { return }
        _ = await transcriptionPrewarmTask.result
        if self.transcriptionPrewarmTask == transcriptionPrewarmTask {
            self.transcriptionPrewarmTask = nil
        }
    }

    private func stopTranscriptionPrewarm() {
        transcriptionPrewarmTask?.cancel()
        transcriptionPrewarmTask = nil
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

        AppLogger.info("AudioStartup \(payload)", category: .perfTrace)
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
}

#if os(macOS)
    extension ConfigurableSpeechService: AudioFeatureSource {}
#endif
