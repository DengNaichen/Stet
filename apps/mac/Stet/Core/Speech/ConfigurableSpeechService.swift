import Foundation

actor ConfigurableSpeechService: SpeechService, AudioLevelSource {
    private let settingsStore: DictationSettingsStore
    private let locale: Locale
    private let pipelineFactory: DictationPipelineFactory
    private let captureServiceFactory: @Sendable () -> any AudioCaptureService
    private let audioLevelBridge = AudioLevelBridge()

    private var activePipeline: DictationPipeline?
    private var activeCaptureService: (any AudioCaptureService)?
    private var audioLevelTask: Task<Void, Never>?

    init(
        settingsStore: DictationSettingsStore = DictationSettingsStore(),
        locale: Locale = .autoupdatingCurrent,
        pipelineFactory: DictationPipelineFactory,
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
        if let captureService {
            self.captureServiceFactory = { captureService }
        } else if let captureServiceFactory {
            self.captureServiceFactory = captureServiceFactory
        } else {
            self.captureServiceFactory = { MacAudioCaptureService() }
        }
    }

    func makeAudioLevelStream() async -> AsyncStream<Double> {
        audioLevelBridge.makeStream()
    }

    func startRecording() async throws {
        guard activePipeline == nil else {
            throw SpeechServiceError.alreadyRecording
        }

        let snapshot = settingsStore.loadSnapshot()
        activePipeline = try await pipelineFactory.makePipeline(from: snapshot)
        let captureService = captureServiceFactory()
        activeCaptureService = captureService

        do {
            try await captureService.startRecording()
            startAudioLevelForwarding(using: captureService)
        } catch {
            activePipeline = nil
            activeCaptureService = nil
            stopAudioLevelForwarding()
            throw error
        }
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
        
        defer {
            try? FileManager.default.removeItem(at: captureResult.url)
        }

        await DictationLatencyProbe.shared.beginSession(audioDurationSeconds: captureResult.duration)

        var transcriptionPrompt: String? = nil
        if let provider = pipeline.promptProvider {
            transcriptionPrompt = await provider()
        }

        AppLogger.info("Submitting transcription request.", category: .dictation)

        var transcript: String
        do {
            transcript = try await pipeline.transcriptionService.transcribe(
                audioFileAt: captureResult.url,
                languageCode: nil,
                prompt: transcriptionPrompt,
                audioDurationSeconds: captureResult.duration
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
                        preferredSpellings: pipeline.preferredSpellings
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

    private func startAudioLevelForwarding(using captureService: any AudioCaptureService) {
        stopAudioLevelForwarding()

        guard let streamingService = captureService as? any AudioLevelSource else { return }
        let audioLevelBridge = self.audioLevelBridge

        audioLevelTask = Task {
            let stream = await streamingService.makeAudioLevelStream()
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
        audioLevelBridge.emit(0)
        audioLevelBridge.finish()
    }
}
