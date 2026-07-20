#if os(macOS)
    @preconcurrency import AVFoundation
    import FluidAudio
    import Foundation
    import StetAI
    import os

    enum FluidAudioTranscriptionError: LocalizedError, Equatable {
        case modelNotDownloaded
        case audioPreparationFailed
        case transcriptionFailed(String)

        nonisolated var errorDescription: String? {
            switch self {
            case .modelNotDownloaded:
                return "Parakeet model is not downloaded. Open Settings → Local Whisper → Download to install it."
            case .audioPreparationFailed:
                return "Stet could not prepare audio for Parakeet transcription."
            case .transcriptionFailed(let message):
                return "Parakeet transcription failed: \(message)"
            }
        }
    }

    /// Transcribes captured audio with the NVIDIA Parakeet ASR model via
    /// FluidAudio. Mirrors `LocalWhisperTranscriptionService`'s reuse-or-transient
    /// pattern: when `LocalParakeetContextManager.shared` already has the right
    /// version loaded the manager is reused; otherwise a transient `AsrManager`
    /// is created, used, and torn down so memory returns to baseline.
    final class FluidAudioTranscriptionService: AudioFileTranscriptionService, @unchecked Sendable {
        private let modelVersion: AsrModelVersion
        private let modelManager: FluidAudioModelManager
        private let modelLoader: @Sendable (AsrModelVersion) async throws -> AsrModels
        private let contextManagerProvider: @MainActor @Sendable () -> LocalParakeetContextManager
        private let logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "com.openwhispr.Stet",
            category: "FluidAudio"
        )

        init(
            modelManager: FluidAudioModelManager = FluidAudioModelManager(),
            modelLoader: (@Sendable (AsrModelVersion) async throws -> AsrModels)? = nil,
            contextManagerProvider: (@MainActor @Sendable () -> LocalParakeetContextManager)? = nil
        ) throws {
            guard modelManager.isModelDownloaded() else {
                throw FluidAudioTranscriptionError.modelNotDownloaded
            }
            self.modelVersion = FluidAudioModelManager.version
            self.modelManager = modelManager
            self.modelLoader =
                modelLoader ?? { version in
                    try await AsrModels.loadFromCache(configuration: nil, version: version)
                }
            self.contextManagerProvider =
                contextManagerProvider ?? { LocalParakeetContextManager.shared }
        }

        /// Loads the ASR model into the shared context manager if nothing is
        /// loaded. Mirrors `LocalWhisperTranscriptionService.prewarm` so the
        /// existing parallel-prewarm path in `ConfigurableSpeechService` works
        /// for both engines.
        func prewarm() async throws {
            let manager = await contextManagerProvider()
            let loader = modelLoader
            let version = modelVersion
            try await manager.loadModel(version: version) { v in
                try await loader(v)
            }
        }

        func transcribe(
            audioFileAt fileURL: URL,
            languageCode: String?,
            prompt: String?,
            audioDurationSeconds: TimeInterval?
        ) async throws -> TranscriptionResult {
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                throw OpenAIError.fileNotFound(fileURL)
            }

            let startedAt = ProcessInfo.processInfo.systemUptime
            let samplePreparationStartedAt = startedAt
            let samples: [Float]
            do {
                samples = try Self.readSamples(from: fileURL)
            } catch {
                logger.error("Failed to prepare audio for Parakeet: \(error.localizedDescription, privacy: .public)")
                throw FluidAudioTranscriptionError.audioPreparationFailed
            }
            let samplePreparationMs = Self.elapsedMilliseconds(since: samplePreparationStartedAt)

            // Pad with 1s of silence so the decoder can emit final punctuation
            // (matches VoiceInk's FluidAudioTranscriptionService behaviour).
            let trailingSilenceSamples = 16_000
            let maxSingleChunkSamples = 240_000
            var paddedSamples = samples
            if paddedSamples.count + trailingSilenceSamples <= maxSingleChunkSamples {
                paddedSamples.append(contentsOf: [Float](repeating: 0, count: trailingSilenceSamples))
            }

            let context = await contextManagerProvider()
            let reusedManager = await context.managerIfLoaded(matching: modelVersion)

            let asrManager: AsrManager
            let isTransient: Bool
            if let reusedManager {
                asrManager = reusedManager
                isTransient = false
            } else {
                let models = try await modelLoader(modelVersion)
                let transient = AsrManager(config: .default)
                try await transient.initialize(models: models)
                asrManager = transient
                isTransient = true
            }

            let inferenceStartedAt = ProcessInfo.processInfo.systemUptime
            let resultText: String
            do {
                let result = try await asrManager.transcribe(paddedSamples, source: .microphone)
                resultText = result.text
            } catch {
                if isTransient {
                    await asrManager.cleanup()
                }
                logger.error(
                    "Parakeet failed audioDurationSeconds=\(Self.formatOptionalDurationSeconds(audioDurationSeconds)) samplePreparationMs=\(Self.formatMilliseconds(samplePreparationMs)) inferenceMs=\(Self.formatMilliseconds(Self.elapsedMilliseconds(since: inferenceStartedAt))) languageCode=\(languageCode ?? "auto") error=\(error.localizedDescription)"
                )
                throw FluidAudioTranscriptionError.transcriptionFailed(error.localizedDescription)
            }
            let inferenceMs = Self.elapsedMilliseconds(since: inferenceStartedAt)
            let totalMs = Self.elapsedMilliseconds(since: startedAt)

            if isTransient {
                await asrManager.cleanup()
            }

            let transcript = resultText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !transcript.isEmpty else {
                throw SpeechServiceError.emptyTranscription
            }

            logger.info(
                "Parakeet completed audioDurationSeconds=\(Self.formatOptionalDurationSeconds(audioDurationSeconds)) sampleCount=\(samples.count) samplePreparationMs=\(Self.formatMilliseconds(samplePreparationMs)) inferenceMs=\(Self.formatMilliseconds(inferenceMs)) totalMs=\(Self.formatMilliseconds(totalMs)) textChars=\(transcript.count) languageCode=\(languageCode ?? "auto") reusedLoadedContext=\(!isTransient)"
            )

            return .init(text: transcript, languageCode: languageCode)
        }

        private nonisolated static func elapsedMilliseconds(since start: TimeInterval) -> Double {
            (ProcessInfo.processInfo.systemUptime - start) * 1_000
        }

        private nonisolated static func formatMilliseconds(_ duration: Double) -> String {
            String(format: "%.1f", duration)
        }

        private nonisolated static func formatOptionalDurationSeconds(_ duration: TimeInterval?) -> String {
            guard let duration, duration.isFinite, duration >= 0 else {
                return "unknown"
            }
            return String(format: "%.3f", duration)
        }

        /// Reads `fileURL` into 16 kHz mono Float32 samples — the format Parakeet
        /// expects. AVFoundation handles whatever container Stet's recorder produced
        /// (WAV/CAF), unlike VoiceInk's path which assumes a fixed 16-bit PCM WAV.
        private static func readSamples(from fileURL: URL) throws -> [Float] {
            let inputFile = try AVAudioFile(forReading: fileURL)
            let inputFormat = inputFile.processingFormat
            let inputFrameCount = AVAudioFrameCount(inputFile.length)

            guard
                let inputBuffer = AVAudioPCMBuffer(
                    pcmFormat: inputFormat,
                    frameCapacity: inputFrameCount
                )
            else {
                throw FluidAudioTranscriptionError.audioPreparationFailed
            }

            try inputFile.read(into: inputBuffer)

            let outputFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 16000,
                channels: 1,
                interleaved: false
            )

            guard let outputFormat else {
                throw FluidAudioTranscriptionError.audioPreparationFailed
            }

            if inputFormat.channelCount == 1,
                inputFormat.commonFormat == .pcmFormatFloat32,
                abs(inputFormat.sampleRate - 16000) < 1,
                let channelData = inputBuffer.floatChannelData
            {
                let frames = Int(inputBuffer.frameLength)
                return Array(UnsafeBufferPointer(start: channelData[0], count: frames))
            }

            guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
                throw FluidAudioTranscriptionError.audioPreparationFailed
            }

            // Output capacity must scale to the destination sample rate.
            let ratio = outputFormat.sampleRate / inputFormat.sampleRate
            let outputCapacity = AVAudioFrameCount(Double(inputBuffer.frameLength) * ratio + 1024)
            guard
                let outputBuffer = AVAudioPCMBuffer(
                    pcmFormat: outputFormat,
                    frameCapacity: outputCapacity
                )
            else {
                throw FluidAudioTranscriptionError.audioPreparationFailed
            }

            var error: NSError?
            var didProvideInput = false
            let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
                guard !didProvideInput else {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                didProvideInput = true
                outStatus.pointee = .haveData
                return inputBuffer
            }

            guard status != .error, error == nil, let channelData = outputBuffer.floatChannelData else {
                throw FluidAudioTranscriptionError.audioPreparationFailed
            }

            let frames = Int(outputBuffer.frameLength)
            return Array(UnsafeBufferPointer(start: channelData[0], count: frames))
        }
    }
#endif
