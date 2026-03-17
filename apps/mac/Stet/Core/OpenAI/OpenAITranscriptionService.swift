import Foundation
import OpenAI

protocol AudioFileTranscriptionService: Sendable {
    func transcribe(
        audioFileAt fileURL: URL,
        languageCode: String?,
        prompt: String?,
        audioDurationSeconds: TimeInterval?
    ) async throws -> String
}

struct OpenAITranscriptionService: AudioFileTranscriptionService {
    private let clientFactory: OpenAISDKClientFactory
    private let defaultModel: String

    nonisolated init(
        configuration: OpenAIConfiguration,
        session: URLSession = .shared
    ) {
        self.clientFactory = OpenAISDKClientFactory(configuration: configuration, session: session)
        self.defaultModel = configuration.transcriptionModel
    }

    func transcribe(
        audioFileAt fileURL: URL,
        languageCode: String? = nil,
        prompt: String? = nil,
        audioDurationSeconds: TimeInterval? = nil
    ) async throws -> String {
        await DictationLatencyProbe.shared.record(.uploadStarted)

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw OpenAIError.fileNotFound(fileURL)
        }

        guard let fileType = AudioTranscriptionQuery.FileType(fileURL: fileURL) else {
            throw OpenAIError.missingTranscriptionText
        }

        let audioData = try Data(contentsOf: fileURL)
        var additionalHeaders: [String: String] = [:]

        if let audioDurationSeconds, audioDurationSeconds.isFinite, audioDurationSeconds > 0 {
            additionalHeaders["X-Stet-Audio-Duration-Seconds"] = String(Int(audioDurationSeconds.rounded(.up)))
        }

        let requestContext = try clientFactory.makeRequestContext(
            additionalHeaders: additionalHeaders,
            additionalMiddlewares: [OpenAIUploadCompletionMiddleware(note: "response_fallback")]
        )

        do {
            let response = try await requestContext.client.audioTranscriptions(
                query: AudioTranscriptionQuery(
                    file: audioData,
                    fileType: fileType,
                    model: defaultModel,
                    prompt: prompt?.trimmingCharacters(in: .whitespacesAndNewlines),
                    language: languageCode?.trimmingCharacters(in: .whitespacesAndNewlines),
                    responseFormat: .json
                )
            )

            let text = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                throw OpenAIError.missingTranscriptionText
            }

            await DictationLatencyProbe.shared.record(.transcriptionCompleted)
            return text
        } catch {
            throw requestContext.mapError(error)
        }
    }
}
