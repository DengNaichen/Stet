import Foundation
import OpenAI

struct RelayDictationTranscriptionService: AudioFileTranscriptionService {
    private struct SuccessResponse: Decodable {
        let text: String
        let rewritten: Bool
    }

    private struct ErrorResponse: Decodable {
        let code: String?
        let message: String
        let request_id: String?
    }

    private enum RequestPolicy {
        static let minimumTimeoutSeconds: TimeInterval = 90
        static let maximumTimeoutSeconds: TimeInterval = 150
        static let timeoutBufferSeconds: TimeInterval = 30
        static let timeoutPerAudioSecond: TimeInterval = 2
    }

    private let authentication: RelayAuthenticationContext
    private let session: URLSession
    private let rewriteEnabled: Bool
    private let preferredSpellings: [String]

    init(
        authentication: RelayAuthenticationContext,
        session: URLSession = .shared,
        rewriteEnabled: Bool,
        preferredSpellings: [String]
    ) {
        self.authentication = authentication
        self.session = session
        self.rewriteEnabled = rewriteEnabled
        self.preferredSpellings = preferredSpellings
    }

    func transcribe(
        audioFileAt fileURL: URL,
        languageCode: String?,
        prompt: String?,
        audioDurationSeconds: TimeInterval?
    ) async throws -> String {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw OpenAIError.fileNotFound(fileURL)
        }

        guard let fileType = AudioTranscriptionQuery.FileType(fileURL: fileURL) else {
            throw AIExecutionError.relayInvocationFailed(
                statusCode: nil,
                message: "The audio format is not supported by Managed Relay.",
                requestID: nil
            )
        }

        guard let audioDurationSeconds,
              audioDurationSeconds.isFinite,
              audioDurationSeconds > 0 else {
            throw AIExecutionError.relayInvocationFailed(
                statusCode: nil,
                message: "Managed Relay requires the audio duration for pay-as-you-go billing.",
                requestID: nil
            )
        }

        let audioData = try Data(contentsOf: fileURL)
        let timeoutInterval = Self.timeoutInterval(for: audioDurationSeconds)
        let clientRequestID = UUID().uuidString
        let request = try Self.makeRequest(
            authentication: authentication,
            audioData: audioData,
            fileType: fileType,
            languageCode: Self.normalizedText(languageCode),
            prompt: Self.normalizedText(prompt),
            audioDurationSeconds: audioDurationSeconds,
            rewriteEnabled: rewriteEnabled,
            preferredSpellings: preferredSpellings,
            timeoutInterval: timeoutInterval,
            clientRequestID: clientRequestID
        )

        AppLogger.info(
            "Relay transcription request started. requestID=\(clientRequestID) url=\(request.url?.absoluteString ?? "unknown") audioBytes=\(audioData.count) fileType=\(fileType.stetContentType) rewriteEnabled=\(rewriteEnabled) preferredSpellingsCount=\(preferredSpellings.count) timeoutSeconds=\(String(format: "%.1f", timeoutInterval))",
            category: .dictation
        )

        do {
            let (responseData, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                AppLogger.error(
                    "Relay transcription returned a non-HTTP response. requestID=\(clientRequestID)",
                    category: .dictation
                )
                throw AIExecutionError.relayInvocationFailed(
                    statusCode: nil,
                    message: "The relay returned an invalid response.",
                    requestID: nil
                )
            }

            AppLogger.info(
                "Relay transcription response received. requestID=\(clientRequestID) status=\(httpResponse.statusCode) responseBytes=\(responseData.count) serverRequestID=\(httpResponse.value(forHTTPHeaderField: "x-request-id") ?? "missing")",
                category: .dictation
            )

            guard (200...299).contains(httpResponse.statusCode) else {
                AppLogger.error(
                    "Relay transcription returned an error response. requestID=\(clientRequestID) status=\(httpResponse.statusCode) responsePreview=\(Self.responsePreview(from: responseData))",
                    category: .dictation
                )
                throw Self.mapRelayError(
                    statusCode: httpResponse.statusCode,
                    responseData: responseData,
                    fallbackRequestID: httpResponse.value(forHTTPHeaderField: "x-request-id")
                )
            }

            let payload = try JSONDecoder().decode(SuccessResponse.self, from: responseData)
            let trimmedText = payload.text.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !trimmedText.isEmpty else {
                AppLogger.error(
                    "Relay transcription succeeded but response text was empty. requestID=\(clientRequestID) serverRequestID=\(httpResponse.value(forHTTPHeaderField: "x-request-id") ?? "missing")",
                    category: .dictation
                )
                throw AIExecutionError.relayInvocationFailed(
                    statusCode: httpResponse.statusCode,
                    message: "The relay response did not contain any text.",
                    requestID: httpResponse.value(forHTTPHeaderField: "x-request-id")
                )
            }

            AppLogger.info(
                "Relay transcription completed. requestID=\(clientRequestID) textLength=\(trimmedText.count)",
                category: .dictation
            )

            return trimmedText
        } catch let error as AIExecutionError {
            AppLogger.error(
                "Relay transcription failed with managed relay error. requestID=\(clientRequestID) error=\(error.localizedDescription)",
                category: .dictation
            )
            throw error
        } catch let error as URLError {
            AppLogger.error(
                "Relay transcription failed with URL error. requestID=\(clientRequestID) code=\(error.code.rawValue) description=\(error.localizedDescription)",
                category: .dictation
            )
            throw AIExecutionError.relayInvocationFailed(
                statusCode: nil,
                message: error.localizedDescription,
                requestID: nil
            )
        } catch {
            AppLogger.error(
                "Relay transcription failed with unexpected client error. requestID=\(clientRequestID) type=\(String(describing: type(of: error))) description=\(error.localizedDescription)",
                category: .dictation
            )
            throw AIExecutionError.relayInvocationFailed(
                statusCode: nil,
                message: error.localizedDescription,
                requestID: nil
            )
        }
    }

    private static func normalizedText(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return nil
        }

        return text
    }

    private static func timeoutInterval(for audioDurationSeconds: TimeInterval?) -> TimeInterval {
        guard let audioDurationSeconds,
              audioDurationSeconds.isFinite,
              audioDurationSeconds > 0 else {
            return RequestPolicy.minimumTimeoutSeconds
        }

        let paddedTimeout = (audioDurationSeconds * RequestPolicy.timeoutPerAudioSecond) + RequestPolicy.timeoutBufferSeconds
        return min(
            max(paddedTimeout, RequestPolicy.minimumTimeoutSeconds),
            RequestPolicy.maximumTimeoutSeconds
        )
    }

    private static func makeRequest(
        authentication: RelayAuthenticationContext,
        audioData: Data,
        fileType: AudioTranscriptionQuery.FileType,
        languageCode: String?,
        prompt: String?,
        audioDurationSeconds: TimeInterval,
        rewriteEnabled: Bool,
        preferredSpellings: [String],
        timeoutInterval: TimeInterval,
        clientRequestID: String
    ) throws -> URLRequest {
        let url = authentication.relayBaseURL.appendingPathComponent("audio/transcriptions")
        let multipart = MultipartFormRequestBody.make(
            fields: makeFields(
                languageCode: languageCode,
                prompt: prompt,
                audioDurationSeconds: audioDurationSeconds,
                rewriteEnabled: rewriteEnabled,
                preferredSpellings: preferredSpellings
            ),
            file: MultipartFormFile(
                name: "file",
                fileName: fileType.stetFileName,
                contentType: fileType.stetContentType,
                data: audioData
            )
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeoutInterval
        request.httpBody = multipart.body
        request.setValue(
            "multipart/form-data; boundary=\(multipart.boundary)",
            forHTTPHeaderField: "Content-Type"
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(authentication.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(authentication.publishableKey, forHTTPHeaderField: "Apikey")
        request.setValue(String(multipart.body.count), forHTTPHeaderField: "Content-Length")
        request.setValue(clientRequestID, forHTTPHeaderField: "x-request-id")
        return request
    }

    private static func makeFields(
        languageCode: String?,
        prompt: String?,
        audioDurationSeconds: TimeInterval,
        rewriteEnabled: Bool,
        preferredSpellings: [String]
    ) -> [MultipartFormField] {
        var fields: [MultipartFormField] = []

        if let languageCode {
            fields.append(.init(name: "language", value: languageCode))
        }

        if let prompt {
            fields.append(.init(name: "prompt", value: prompt))
        }

        fields.append(
            .init(
                name: "audio_duration_seconds",
                value: String(format: "%.3f", audioDurationSeconds)
            )
        )

        if rewriteEnabled {
            fields.append(.init(name: "rewrite", value: "true"))
        }

        let normalizedPreferredSpellings = preferredSpellings
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if !normalizedPreferredSpellings.isEmpty {
            fields.append(
                .init(
                    name: "preferred_spellings",
                    value: normalizedPreferredSpellings.joined(separator: ", ")
                )
            )
        }

        return fields
    }

    private static func mapRelayError(
        statusCode: Int,
        responseData: Data,
        fallbackRequestID: String?
    ) -> AIExecutionError {
        if let payload = try? JSONDecoder().decode(ErrorResponse.self, from: responseData) {
            let message = payload.code.map { "[\($0)] \(payload.message)" } ?? payload.message
            return .relayInvocationFailed(
                statusCode: statusCode,
                message: message,
                requestID: payload.request_id ?? fallbackRequestID
            )
        }

        if let rawText = String(data: responseData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !rawText.isEmpty {
            return .relayInvocationFailed(
                statusCode: statusCode,
                message: rawText,
                requestID: fallbackRequestID
            )
        }

        return .relayInvocationFailed(
            statusCode: statusCode,
            message: HTTPURLResponse.localizedString(forStatusCode: statusCode),
            requestID: fallbackRequestID
        )
    }

    private static func responsePreview(from data: Data) -> String {
        guard let text = String(data: data, encoding: .utf8)?
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return "<empty>"
        }

        let limit = 500
        if text.count <= limit {
            return text
        }

        let endIndex = text.index(text.startIndex, offsetBy: limit)
        return "\(text[..<endIndex])…"
    }
}
