import Foundation
import OpenAI

struct OpenAISDKClientFactory: Sendable {
    private let configuration: OpenAIConfiguration
    private let session: URLSession

    nonisolated init(
        configuration: OpenAIConfiguration,
        session: URLSession = .shared
    ) {
        self.configuration = configuration
        self.session = session
    }

    nonisolated func makeRequestContext(
        additionalHeaders: [String: String] = [:],
        additionalMiddlewares: [any OpenAIMiddleware] = []
    ) throws -> OpenAISDKRequestContext {
        let responseRecorder = OpenAIHTTPResponseRecorder()
        var middlewares: [any OpenAIMiddleware] = [
            OpenAILoggingMiddleware(),
            OpenAIResponseRecordingMiddleware(responseRecorder: responseRecorder),
        ]
        middlewares.append(contentsOf: additionalMiddlewares)

        return OpenAISDKRequestContext(
            client: OpenAI(
                configuration: try configuration.sdkConfiguration(additionalHeaders: additionalHeaders),
                session: session,
                middlewares: middlewares
            ),
            responseRecorder: responseRecorder
        )
    }
}

struct OpenAISDKRequestContext {
    let client: OpenAI

    private let responseRecorder: OpenAIHTTPResponseRecorder

    fileprivate nonisolated init(client: OpenAI, responseRecorder: OpenAIHTTPResponseRecorder) {
        self.client = client
        self.responseRecorder = responseRecorder
    }

    nonisolated func mapError(_ error: any Error) -> any Error {
        OpenAISDKErrorMapper.map(error, responseStatusCode: responseRecorder.statusCode)
    }
}

private enum OpenAISDKErrorMapper {
    static func map(_ error: any Error, responseStatusCode: Int?) -> any Error {
        if let error = error as? OpenAIError {
            return error
        }

        if let error = error as? APIErrorResponse {
            return OpenAIError.api(
                statusCode: responseStatusCode,
                message: error.error.message
            )
        }

        if error is DecodingError {
            if let responseStatusCode, responseStatusCode >= 400 {
                return OpenAIError.api(
                    statusCode: responseStatusCode,
                    message: HTTPURLResponse.localizedString(forStatusCode: responseStatusCode)
                )
            }
            return OpenAIError.invalidResponse
        }

        return error
    }
}

fileprivate final class OpenAIHTTPResponseRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var latestStatusCode: Int?

    nonisolated init() {}

    nonisolated var statusCode: Int? {
        lock.lock()
        defer { lock.unlock() }
        return latestStatusCode
    }

    nonisolated func record(_ response: URLResponse?) {
        guard let httpResponse = response as? HTTPURLResponse else { return }

        lock.lock()
        latestStatusCode = httpResponse.statusCode
        lock.unlock()
    }
}

private struct OpenAIResponseRecordingMiddleware: OpenAIMiddleware {
    let responseRecorder: OpenAIHTTPResponseRecorder

    func intercept(response: URLResponse?, request: URLRequest, data: Data?) -> (response: URLResponse?, data: Data?) {
        responseRecorder.record(response)
        return (response, data)
    }
}

private struct OpenAILoggingMiddleware: OpenAIMiddleware {
    func intercept(request: URLRequest) -> URLRequest {
        AppLogger.info(
            "OpenAI request started. method=\(request.httpMethod ?? "GET"), url=\(request.url?.absoluteString ?? "nil")",
            category: .openAI
        )

        return request
    }

    func intercept(response: URLResponse?, request: URLRequest, data: Data?) -> (response: URLResponse?, data: Data?) {
        if let httpResponse = response as? HTTPURLResponse {
            AppLogger.info(
                "OpenAI response received. status=\(httpResponse.statusCode), url=\(request.url?.absoluteString ?? "nil")",
                category: .openAI
            )
        }

        return (response, data)
    }
}

struct OpenAIUploadCompletionMiddleware: OpenAIMiddleware {
    let note: String?

    func intercept(response: URLResponse?, request: URLRequest, data: Data?) -> (response: URLResponse?, data: Data?) {
        Task {
            await DictationLatencyProbe.shared.ensureUploadCompleted(note: note)
        }

        return (response, data)
    }
}

extension OpenAIConfiguration {
    nonisolated func sdkConfiguration(additionalHeaders: [String: String] = [:]) throws -> OpenAI.Configuration {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw OpenAIError.missingAPIKey
        }

        let normalizedBaseURL = baseURL.hasDirectoryPath
            ? baseURL
            : baseURL.appendingPathComponent("")

        guard let components = URLComponents(url: normalizedBaseURL, resolvingAgainstBaseURL: false),
              let scheme = components.scheme,
              let host = components.host else {
            throw OpenAIError.invalidBaseURL
        }

        var customHeaders: [String: String] = [:]

        if let projectID = trimmedValue(projectID) {
            customHeaders["OpenAI-Project"] = projectID
        }

        for (header, value) in additionalHeaders {
            if let trimmedValue = trimmedValue(value) {
                customHeaders[header] = trimmedValue
            }
        }

        return OpenAI.Configuration(
            token: trimmedKey,
            organizationIdentifier: trimmedValue(organizationID),
            host: host,
            port: components.port ?? Self.defaultPort(for: scheme),
            scheme: scheme,
            basePath: components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath,
            timeoutInterval: 60,
            customHeaders: customHeaders,
            parsingOptions: Self.requiresRelaxedParsing(for: normalizedBaseURL) ? .relaxed : []
        )
    }

    private static func requiresRelaxedParsing(for baseURL: URL) -> Bool {
        guard let host = baseURL.host?.lowercased() else { return false }
        return host != "api.openai.com" && !host.hasSuffix(".openai.com")
    }

    private static func defaultPort(for scheme: String) -> Int {
        switch scheme.lowercased() {
        case "http":
            return 80
        case "https":
            return 443
        default:
            return 443
        }
    }

    private func trimmedValue(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }

        return value
    }
}

extension ResponseObject {
    var stetOutputText: String? {
        for item in output {
            guard case .outputMessage(let message) = item else {
                continue
            }

            for content in message.content {
                guard case .OutputTextContent(let outputText) = content else {
                    continue
                }

                let text = outputText.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    return text
                }
            }
        }

        return nil
    }
}

extension AudioTranscriptionQuery.FileType {
    init?(fileURL: URL) {
        switch fileURL.pathExtension.lowercased() {
        case "flac":
            self = .flac
        case "m4a":
            self = .m4a
        case "mp3":
            self = .mp3
        case "mp4":
            self = .mp4
        case "mpeg":
            self = .mpeg
        case "mpga":
            self = .mpga
        case "ogg":
            self = .ogg
        case "wav":
            self = .wav
        case "webm":
            self = .webm
        default:
            return nil
        }
    }
}
