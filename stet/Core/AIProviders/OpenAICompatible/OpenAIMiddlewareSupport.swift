import Foundation
import OpenAI
import os

// MARK: - Http Response Recorder

nonisolated final class OpenAIHTTPResponseRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var latestStatusCode: Int?
    private var latestData: Data?

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
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.openwhispr.Stet", category: "openai")

    func intercept(request: URLRequest) -> URLRequest {
        logger.info(
            "\(provider.displayName) request started. method=\(request.httpMethod ?? "GET"), url=\(request.url?.absoluteString ?? "nil")"
        )

        return request
    }

    func intercept(response: URLResponse?, request: URLRequest, data: Data?) -> (response: URLResponse?, data: Data?) {
        if let httpResponse = response as? HTTPURLResponse {
            logger.info(
                "\(provider.displayName) response received. status=\(httpResponse.statusCode), url=\(request.url?.absoluteString ?? "nil")"
            )
        }

        return (response, data)
    }
}
