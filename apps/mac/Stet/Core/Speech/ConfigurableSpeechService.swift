import Foundation

actor ConfigurableSpeechService: SpeechService, AudioLevelSource {
    private let settingsStore: DictationSettingsStore
    private let locale: Locale
    private let pipelineFactory: DictationPipelineFactory
    private let captureServiceFactory: @Sendable () -> any AudioCaptureService
    private let audioPostProcessor: any AudioPostProcessing
    private let audioLevelBridge = AudioLevelBridge()

    private var activePipeline: DictationPipeline?
    private var activeCaptureService: (any AudioCaptureService)?
    private var audioLevelTask: Task<Void, Never>?
    private var reusableCaptureService: (any AudioCaptureService)?

    init(
        settingsStore: DictationSettingsStore = DictationSettingsStore(),
        locale: Locale = .autoupdatingCurrent,
        pipelineFactory: DictationPipelineFactory,
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
        activePipeline = try await pipelineFactory.makePipeline(from: snapshot)
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
        } catch is CancellationError {
            activePipeline = nil
            activeCaptureService = nil
            stopAudioLevelForwarding()
            await DictationStartupProbe.shared.record(.cancelled)
            throw CancellationError()
        } catch {
            activePipeline = nil
            activeCaptureService = nil
            stopAudioLevelForwarding()
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

    func stopRecording() async throws -> String {
        guard let pipeline = activePipeline,
              let captureService = activeCaptureService else {
            throw SpeechServiceError.notRecording
        }

        defer {
            self.activePipeline = nil
            self.activeCaptureService = nil
            stopAudioLevelForwarding()
        }

        let captureResult = try await captureService.stopRecording()
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

        var transcriptionPrompt: String? = nil
        if let provider = pipeline.promptProvider {
            transcriptionPrompt = await provider()
        }

        AppLogger.info("Submitting transcription request.", category: .dictation)

        var transcript: String
        do {
            transcript = try await pipeline.transcriptionService.transcribe(
                audioFileAt: processedCaptureResult.url,
                languageCode: pipeline.transcriptionLanguageCode,
                prompt: transcriptionPrompt,
                audioDurationSeconds: processedCaptureResult.duration
            )
            transcript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !transcript.isEmpty else {
                throw SpeechServiceError.emptyTranscription
            }
        } catch {
            await DictationLatencyProbe.shared.record(.transcriptionFailed, note: error.localizedDescription)
            AppLogger.error("Transcription failed: \(error.localizedDescription)", category: .dictation)
            throw error
        }

        do {
            if let rewriteService = pipeline.rewriteService {
                transcript = try await rewriteService.rewrite(
                    .cleanup(
                        transcript,
                        preferredSpellings: pipeline.preferredSpellings,
                        additionalUserContext: pipeline.rewriteAdditionalContext
                    )
                )
            }

            let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedTranscript.isEmpty else {
                throw SpeechServiceError.emptyTranscription
            }

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
        let captureService = activeCaptureService
        activeCaptureService = nil
        stopAudioLevelForwarding()
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
}
