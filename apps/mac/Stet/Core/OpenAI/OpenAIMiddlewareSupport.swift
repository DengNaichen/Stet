import Foundation
import OpenAI

// MARK: - Http Response Recorder

final class OpenAIHTTPResponseRecorder: @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var latestStatusCode: Int?
    nonisolated(unsafe) private var latestData: Data?

    nonisolated init() {}

    nonisolated var statusCode: Int? {
        lock.lock()
        defer { lock.unlock() }
        return latestStatusCode
    }

    nonisolated var data: Data? {
        lock.lock()
        defer { lock.unlock() }
        return latestData
    }

    nonisolated func record(_ response: URLResponse?, data: Data?) {
        guard let httpResponse = response as? HTTPURLResponse else { return }

        lock.lock()
        latestStatusCode = httpResponse.statusCode
        latestData = data
        lock.unlock()
    }
}

// MARK: - Middlewares

struct OpenAIResponseRecordingMiddleware: OpenAIMiddleware {
    let responseRecorder: OpenAIHTTPResponseRecorder

    func intercept(response: URLResponse?, request: URLRequest, data: Data?) -> (response: URLResponse?, data: Data?) {
        responseRecorder.record(response, data: data)
        return (response, data)
    }
}

struct OpenAILoggingMiddleware: OpenAIMiddleware {
    let provider: DictationProvider

    func intercept(request: URLRequest) -> URLRequest {
        AppLogger.info(
            "\(provider.displayName) request started. method=\(request.httpMethod ?? "GET"), url=\(request.url?.absoluteString ?? "nil")",
            category: .openAI
        )

        return request
    }

    func intercept(response: URLResponse?, request: URLRequest, data: Data?) -> (response: URLResponse?, data: Data?) {
        if let httpResponse = response as? HTTPURLResponse {
            AppLogger.info(
                "\(provider.displayName) response received. status=\(httpResponse.statusCode), url=\(request.url?.absoluteString ?? "nil")",
                category: .openAI
            )
        }

        return (response, data)
    }
}
