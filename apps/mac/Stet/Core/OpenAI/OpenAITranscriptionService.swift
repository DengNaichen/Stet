import Foundation

protocol AudioFileTranscriptionService: Sendable {
    func transcribe(
        audioFileAt fileURL: URL,
        languageCode: String?,
        prompt: String?,
        audioDurationSeconds: TimeInterval?
    ) async throws -> String
}

struct OpenAITranscriptionService: AudioFileTranscriptionService {
    private struct ResponseEnvelope: Decodable {
        let text: String?
    }

    private let client: OpenAIClient
    private let defaultModel: String

    nonisolated init(
        configuration: OpenAIConfiguration,
        session: URLSession = .shared
    ) {
        self.client = OpenAIClient(configuration: configuration, session: session)
        self.defaultModel = configuration.transcriptionModel
    }

    func transcribe(
        audioFileAt fileURL: URL,
        languageCode: String? = nil,
        prompt: String? = nil,
        audioDurationSeconds: TimeInterval? = nil
    ) async throws -> String {
        await DictationLatencyProbe.shared.record(.uploadStarted)

        var fields = ["model": defaultModel]
        var additionalHeaders: [String: String] = [:]

        if let languageCode = languageCode?.trimmingCharacters(in: .whitespacesAndNewlines),
           !languageCode.isEmpty {
            fields["language"] = languageCode
        }

        if let prompt = prompt?.trimmingCharacters(in: .whitespacesAndNewlines),
           !prompt.isEmpty {
            fields["prompt"] = prompt
        }

        if let audioDurationSeconds, audioDurationSeconds.isFinite, audioDurationSeconds > 0 {
            additionalHeaders["X-Stet-Audio-Duration-Seconds"] = String(Int(audioDurationSeconds.rounded(.up)))
        }

        let response: ResponseEnvelope = try await client.sendMultipartRequest(
            path: "/audio/transcriptions",
            fields: fields,
            file: .init(fileURL: fileURL),
            additionalHeaders: additionalHeaders,
            trackLatencyProbe: true
        )

        guard let text = response.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            throw OpenAIError.missingTranscriptionText
        }

        await DictationLatencyProbe.shared.record(.transcriptionCompleted)
        return text
    }
}
