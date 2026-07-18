import Foundation
import StetASR

/// App-level adapter for the shared SenseVoice file transcriber.
///
/// macOS keeps its existing capture-to-file workflow. The actual model loading
/// and Sherpa-ONNX inference live in `StetASR`, alongside the iOS live engine.
final class SherpaOnnxSenseVoiceTranscriptionService: AudioFileTranscriptionService, @unchecked Sendable {
    private let transcriber: SenseVoiceFileTranscriber

    nonisolated init() throws {
        self.transcriber = SenseVoiceFileTranscriber(modelManager: try SenseVoiceModelManager())
    }

    func prewarm() async throws {
        try await transcriber.prewarm()
    }

    func transcribe(
        audioFileAt fileURL: URL,
        languageCode: String?,
        prompt _: String?,
        audioDurationSeconds _: TimeInterval?
    ) async throws -> TranscriptionResult {
        let result = try await transcriber.transcribe(
            audioFileAt: fileURL,
            languageCode: languageCode
        )
        guard !result.text.isEmpty else {
            throw SpeechServiceError.emptyTranscription
        }
        return TranscriptionResult(text: result.text, languageCode: result.languageCode)
    }
}
