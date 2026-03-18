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
        additionalMiddlewares: [any OpenAIMiddleware] = [],
        timeoutInterval: TimeInterval? = nil
    ) throws -> OpenAISDKRequestContext {
        let responseRecorder = OpenAIHTTPResponseRecorder()
        var middlewares: [any OpenAIMiddleware] = [
            OpenAILoggingMiddleware(provider: configuration.provider),
            OpenAIResponseRecordingMiddleware(responseRecorder: responseRecorder),
        ]
        middlewares.append(contentsOf: additionalMiddlewares)

        return OpenAISDKRequestContext(
            client: OpenAI(
                configuration: try configuration.sdkConfiguration(
                    additionalHeaders: additionalHeaders,
                    timeoutInterval: timeoutInterval
                ),
                session: session,
                middlewares: middlewares
            ),
            responseRecorder: responseRecorder,
            provider: configuration.provider
        )
    }
}

struct OpenAISDKRequestContext {
    let client: OpenAI

    private let responseRecorder: OpenAIHTTPResponseRecorder
    private let provider: DictationProvider

    fileprivate nonisolated init(
        client: OpenAI,
        responseRecorder: OpenAIHTTPResponseRecorder,
        provider: DictationProvider
    ) {
        self.client = client
        self.responseRecorder = responseRecorder
        self.provider = provider
    }

    nonisolated func mapError(_ error: any Error) -> any Error {
        OpenAISDKErrorMapper.map(
            error,
            responseStatusCode: responseRecorder.statusCode,
            provider: provider
        )
    }

    nonisolated var responseStatusCode: Int? {
        responseRecorder.statusCode
    }

    nonisolated var responseData: Data? {
        responseRecorder.data
    }
}
