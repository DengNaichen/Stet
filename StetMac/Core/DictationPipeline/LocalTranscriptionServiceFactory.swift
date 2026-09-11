#if os(macOS)
    import Foundation
    import StetCore
    import os

    /// Deep module for selecting and preparing the local transcription engine.
    /// Parakeet falls back to Fun-ASR Nano; Fun-ASR has no further fallback.
    struct LocalTranscriptionServiceFactory: Sendable {
        nonisolated static func make(
            configuration: any ModelStorageConfiguration = UserDefaultsModelStorage()
        ) throws -> any AudioFileTranscriptionService {
            let stored = configuration.transcriptionEngine
            let logger = Logger(
                subsystem: Bundle.main.bundleIdentifier ?? "com.openwhispr.Stet",
                category: "PipelineFactory"
            )
            logger.info("DictationPipelineFactory selected local engine=\(stored.rawValue)")

            switch stored {
            case .fluidAudio:
                do {
                    return try FluidAudioTranscriptionService()
                } catch {
                    logger.warning(
                        "Selected transcription engine unavailable (\(error.localizedDescription)); falling back to Fun-ASR Nano."
                    )
                    return try FunASRNanoTranscriptionService()
                }
            case .funASRNano:
                return try FunASRNanoTranscriptionService()
            }
        }
    }
#endif
