import Foundation
import StetCore
import os

/// Deep module for selecting and preparing the local transcription engine.
/// Its interface is one configuration in, one ready service out; fallback and diagnostics stay local.
struct LocalTranscriptionServiceFactory: Sendable {
    nonisolated static func make(
        configuration: any ModelStorageConfiguration = UserDefaultsModelStorage()
    ) throws -> any AudioFileTranscriptionService {
        #if os(macOS)
            let stored = configuration.transcriptionEngine
            let logger = Logger(
                subsystem: Bundle.main.bundleIdentifier ?? "com.openwhispr.Stet",
                category: "PipelineFactory"
            )
            logger.info("DictationPipelineFactory selected local engine=\(stored.rawValue)")

            switch stored {
            case .fluidAudio:
                return try makeWithFallback(logger: logger, configuration: configuration) {
                    try FluidAudioTranscriptionService()
                }
            case .funASRNano:
                return try makeWithFallback(logger: logger, configuration: configuration) {
                    try FunASRNanoTranscriptionService()
                }
            case .localWhisper:
                return try LocalWhisperTranscriptionService(
                    modelManager: LocalWhisperModelManager(configuration: configuration)
                )
            }
        #else
            return try LocalWhisperTranscriptionService(
                modelManager: LocalWhisperModelManager(configuration: configuration)
            )
        #endif
    }

    #if os(macOS)
        private nonisolated static func makeWithFallback(
            logger: Logger,
            configuration: any ModelStorageConfiguration,
            makePrimary: () throws -> any AudioFileTranscriptionService
        ) throws -> any AudioFileTranscriptionService {
            do {
                return try makePrimary()
            } catch {
                logger.warning(
                    "Selected transcription engine unavailable (\(error.localizedDescription)); falling back to local whisper."
                )
                return try LocalWhisperTranscriptionService(
                    modelManager: LocalWhisperModelManager(configuration: configuration)
                )
            }
        }
    #endif
}
