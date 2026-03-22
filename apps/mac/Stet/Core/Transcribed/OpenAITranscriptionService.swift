import Foundation
import OpenAI

struct OpenAITranscriptionService: AudioFileTranscriptionService {
    private struct APIErrorEnvelope: Decodable {
        let error: APIErrorPayload
    }

    private struct APIErrorPayload: Decodable {
        let message: String
    }

    private enum RequestPolicy {
        static let maxAttempts = 3
        static let minimumTimeoutSeconds: TimeInterval = 90
        static let maximumTimeoutSeconds: TimeInterval = 300
        static let timeoutBufferSeconds: TimeInterval = 30
        static let timeoutPerAudioSecond: TimeInterval = 2
    }

    private let configuration: OpenAIConfiguration
    private let session: URLSession
    private let defaultModel: String
    private let provider: DictationProvider

    nonisolated init(
        configuration: OpenAIConfiguration,
        session: URLSession = .shared
    ) {
        self.configuration = configuration
        self.session = session
        self.defaultModel = configuration.transcriptionModel
        self.provider = configuration.provider
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
        let trimmedPrompt = Self.normalizedText(prompt)
        let trimmedLanguageCode = Self.normalizedText(languageCode)
        let timeoutInterval = Self.timeoutInterval(for: audioDurationSeconds)

        if let audioDurationSeconds, audioDurationSeconds.isFinite, audioDurationSeconds > 0 {
            additionalHeaders["X-Stet-Audio-Duration-Seconds"] = String(Int(audioDurationSeconds.rounded(.up)))
        }

        var lastRetriableError: (any Error)?

        for attempt in 1...RequestPolicy.maxAttempts {
            var responseStatusCode: Int?

            do {
                let request = try Self.makeTranscriptionRequest(
                    configuration: configuration,
                    audioData: audioData,
                    fileType: fileType,
                    model: defaultModel,
                    prompt: trimmedPrompt,
                    languageCode: trimmedLanguageCode,
                    additionalHeaders: additionalHeaders,
                    timeoutInterval: timeoutInterval
                )
                AppLogger.info(
                    "\(provider.displayName) request started. method=\(request.httpMethod ?? "POST"), url=\(request.url?.absoluteString ?? "nil")",
                    category: .openAI
                )
                let (responseData, response) = try await session.data(for: request)
                await DictationLatencyProbe.shared.ensureUploadCompleted(note: "http_response")

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw OpenAIError.invalidResponse(provider: provider)
                }

                responseStatusCode = httpResponse.statusCode
                AppLogger.info(
                    "\(provider.displayName) response received. status=\(httpResponse.statusCode), url=\(request.url?.absoluteString ?? "nil")",
                    category: .openAI
                )

                if let text = Self.transcriptionText(from: responseData, statusCode: httpResponse.statusCode) {
                    if Self.responseLooksLikeFallbackText(responseData) {
                        AppLogger.warning(
                            "Recovered transcription text from raw response body after nonstandard transcription payload.",
                            category: .openAI
                        )
                    }

                    await DictationLatencyProbe.shared.record(.transcriptionCompleted)
                    return text
                }

                guard (200...299).contains(httpResponse.statusCode) else {
                    throw Self.apiError(
                        provider: provider,
                        statusCode: httpResponse.statusCode,
                        responseData: responseData
                    )
                }

                throw OpenAIError.missingTranscriptionText
            } catch {
                let mappedError = Self.mapRequestError(
                    error,
                    provider: provider,
                    responseStatusCode: responseStatusCode
                )
                guard Self.shouldRetry(error: mappedError, attempt: attempt) else {
                    throw mappedError
                }

                lastRetriableError = mappedError
                let retryDelay = Self.retryDelay(forAttempt: attempt)
                AppLogger.warning(
                    "Transient transcription failure. attempt=\(attempt) status=\(responseStatusCode.map(String.init) ?? "none") error=\(mappedError.localizedDescription) retryDelayMs=\(Self.retryDelayMilliseconds(for: retryDelay))",
                    category: .openAI
                )
                try? await Task.sleep(for: retryDelay)
            }
        }

        throw lastRetriableError ?? OpenAIError.invalidResponse(provider: provider)
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

    private static func makeTranscriptionRequest(
        configuration: OpenAIConfiguration,
        audioData: Data,
        fileType: AudioTranscriptionQuery.FileType,
        model: String,
        prompt: String?,
        languageCode: String?,
        additionalHeaders: [String: String],
        timeoutInterval: TimeInterval
    ) throws -> URLRequest {
        let sdkConfiguration = try configuration.sdkConfiguration(
            additionalHeaders: additionalHeaders,
            timeoutInterval: timeoutInterval
        )
        let url = try transcriptionURL(from: sdkConfiguration)
        let multipart = MultipartFormRequestBody.make(
            fields: makeMultipartFields(
                model: model,
                prompt: prompt,
                languageCode: languageCode
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
        request.setValue(String(multipart.body.count), forHTTPHeaderField: "Content-Length")

        if let token = sdkConfiguration.token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let organizationIdentifier = sdkConfiguration.organizationIdentifier {
            request.setValue(organizationIdentifier, forHTTPHeaderField: "OpenAI-Organization")
        }

        for (headerField, value) in sdkConfiguration.customHeaders {
            request.setValue(value, forHTTPHeaderField: headerField)
        }

        return request
    }

    private static func transcriptionURL(from sdkConfiguration: OpenAI.Configuration) throws -> URL {
        var components = URLComponents()
        components.scheme = sdkConfiguration.scheme
        components.host = sdkConfiguration.host
        components.port = sdkConfiguration.port

        let normalizedBasePath: String
        if sdkConfiguration.basePath == "/" {
            normalizedBasePath = ""
        } else {
            normalizedBasePath = sdkConfiguration.basePath.hasSuffix("/")
                ? String(sdkConfiguration.basePath.dropLast())
                : sdkConfiguration.basePath
        }

        components.path = "\(normalizedBasePath)/audio/transcriptions"

        guard let url = components.url else {
            throw OpenAIError.invalidBaseURL(
                provider: configurationProvider(
                    host: sdkConfiguration.host
                )
            )
        }

        return url
    }

    private static func makeMultipartFields(
        model: String,
        prompt: String?,
        languageCode: String?
    ) -> [MultipartFormField] {
        var fields: [MultipartFormField] = [
            .init(name: "model", value: model),
            .init(name: "response_format", value: "json"),
        ]

        if let prompt {
            fields.append(.init(name: "prompt", value: prompt))
        }

        if let languageCode {
            fields.append(.init(name: "language", value: languageCode))
        }

        return fields
    }

    private static func transcriptionText(from responseData: Data, statusCode: Int) -> String? {
        guard (200...299).contains(statusCode),
              !responseData.isEmpty else {
            return nil
        }

        if let payload = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
           let text = normalizedText(payload["text"] as? String) {
            return text
        }

        guard let rawText = String(data: responseData, encoding: .utf8),
              let normalizedRawText = normalizedText(rawText) else {
            return nil
        }

        if normalizedRawText.hasPrefix("{") || normalizedRawText.hasPrefix("[") || normalizedRawText.hasPrefix("<") {
            return nil
        }

        return normalizedRawText
    }

    private static func responseLooksLikeFallbackText(_ responseData: Data) -> Bool {
        guard let rawText = String(data: responseData, encoding: .utf8),
              let normalizedRawText = normalizedText(rawText) else {
            return false
        }

        return !normalizedRawText.hasPrefix("{")
            && !normalizedRawText.hasPrefix("[")
            && !normalizedRawText.hasPrefix("<")
    }

    private static func apiError(
        provider: DictationProvider,
        statusCode: Int,
        responseData: Data
    ) -> OpenAIError {
        if let envelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: responseData),
           let message = normalizedText(envelope.error.message) {
            return OpenAIError.api(
                provider: provider,
                statusCode: statusCode,
                message: message
            )
        }

        if let rawText = String(data: responseData, encoding: .utf8),
           let message = normalizedText(rawText),
           !message.hasPrefix("<") {
            return OpenAIError.api(
                provider: provider,
                statusCode: statusCode,
                message: message
            )
        }

        return OpenAIError.api(
            provider: provider,
            statusCode: statusCode,
            message: HTTPURLResponse.localizedString(forStatusCode: statusCode)
        )
    }

    private static func mapRequestError(
        _ error: any Error,
        provider: DictationProvider,
        responseStatusCode: Int?
    ) -> any Error {
        if let openAIError = error as? OpenAIError {
            return openAIError
        }

        if let responseStatusCode,
           let decodingError = error as? DecodingError {
            _ = decodingError
            return OpenAIError.api(
                provider: provider,
                statusCode: responseStatusCode,
                message: HTTPURLResponse.localizedString(forStatusCode: responseStatusCode)
            )
        }

        return error
    }

    private static func configurationProvider(host: String) -> DictationProvider {
        if host.lowercased() == "api.groq.com" || host.lowercased().hasSuffix(".groq.com") {
            return .groq
        }

        return .openAI
    }

    private static func shouldRetry(error: any Error, attempt: Int) -> Bool {
        guard attempt < RequestPolicy.maxAttempts else {
            return false
        }

        if let openAIError = error as? OpenAIError {
            switch openAIError {
            case .api(_, let statusCode, _):
                return retryableStatusCodes.contains(statusCode ?? -1)
            case .invalidResponse, .missingTranscriptionText:
                return true
            case .missingAPIKey, .invalidBaseURL, .fileNotFound, .missingRewriteText:
                return false
            }
        }

        if let urlError = error as? URLError {
            return retryableURLErrorCodes.contains(urlError.code)
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            let code = URLError.Code(rawValue: nsError.code)
            return retryableURLErrorCodes.contains(code)
        }

        return false
    }

    private static func retryDelay(forAttempt attempt: Int) -> Duration {
        switch attempt {
        case 1:
            return .milliseconds(350)
        case 2:
            return .milliseconds(1_000)
        default:
            return .milliseconds(1_500)
        }
    }

    private static func retryDelayMilliseconds(for delay: Duration) -> Int {
        let components = delay.components
        return Int(components.seconds * 1_000) + Int(components.attoseconds / 1_000_000_000_000_000)
    }

    private static let retryableStatusCodes: Set<Int> = [408, 409, 429, 500, 502, 503, 504]
    private static let retryableURLErrorCodes: Set<URLError.Code> = [
        .badServerResponse,
        .callIsActive,
        .cannotConnectToHost,
        .cannotFindHost,
        .dataNotAllowed,
        .dnsLookupFailed,
        .internationalRoamingOff,
        .networkConnectionLost,
        .notConnectedToInternet,
        .resourceUnavailable,
        .timedOut
    ]
}
