import Foundation
import StetAI
import StetCore
import StetRewrite
import Testing

@Suite("Cloud Structured Rewrite", .serialized)
struct CloudStructuredRewriteTests {
    @Test func openAIRequestsStrictSchemaAndExtractsText() async throws {
        let session = TestHTTP.makeSession { request in
            let body = try TestHTTP.jsonBody(from: request)
            let textConfiguration = try #require(body["text"] as? [String: Any])
            let format = try #require(textConfiguration["format"] as? [String: Any])
            #expect(format["type"] as? String == "json_schema")
            #expect(format["name"] as? String == "rewrite_output")
            #expect(format["strict"] as? Bool == true)
            let schema = try #require(format["schema"] as? [String: Any])
            #expect(schema["required"] as? [String] == ["text"])
            #expect(schema["additionalProperties"] as? Bool == false)

            return try TestHTTP.response(
                for: request,
                body: #"{"output":[{"content":[{"type":"output_text","text":"{\"text\":\"OpenAI rewrite\"}"}]}]}"#
            )
        }
        let service = OpenAIRewriteService(
            configuration: makeConfiguration(provider: .openAI),
            session: session
        )

        let text = try await service.rewrite(.cleanup("hello"))

        #expect(text == "OpenAI rewrite")
    }

    @Test func deepSeekRequestsJSONObjectAndExtractsText() async throws {
        let session = TestHTTP.makeSession { request in
            let body = try TestHTTP.jsonBody(from: request)
            let responseFormat = try #require(body["response_format"] as? [String: Any])
            #expect(responseFormat["type"] as? String == "json_object")
            let messages = try #require(body["messages"] as? [[String: Any]])
            #expect((messages.last?["content"] as? String)?.contains("Return exactly one JSON object") == true)

            return try TestHTTP.response(
                for: request,
                body: #"{"choices":[{"message":{"content":"{\"text\":\"DeepSeek rewrite\"}"}}]}"#
            )
        }
        let service = OpenAIRewriteService(
            configuration: makeConfiguration(provider: .deepSeek),
            session: session
        )

        let text = try await service.rewrite(.cleanup("hello"))

        #expect(text == "DeepSeek rewrite")
    }

    @Test func groqGPTOSSRequestsStrictSchema() async throws {
        let session = TestHTTP.makeSession { request in
            let body = try TestHTTP.jsonBody(from: request)
            let responseFormat = try #require(body["response_format"] as? [String: Any])
            #expect(responseFormat["type"] as? String == "json_schema")
            let jsonSchema = try #require(responseFormat["json_schema"] as? [String: Any])
            #expect(jsonSchema["strict"] as? Bool == true)

            return try TestHTTP.response(
                for: request,
                body: #"{"choices":[{"message":{"content":"{\"text\":\"Groq rewrite\"}"}}]}"#
            )
        }
        let service = OpenAIRewriteService(
            configuration: makeConfiguration(provider: .groq),
            session: session
        )

        let text = try await service.rewrite(.cleanup("hello"))

        #expect(text == "Groq rewrite")
    }

    @Test func googleRequestsSchemaAndExtractsText() async throws {
        let session = TestHTTP.makeSession { request in
            let body = try TestHTTP.jsonBody(from: request)
            let generationConfig = try #require(body["generationConfig"] as? [String: Any])
            #expect(generationConfig["responseMimeType"] as? String == "application/json")
            let schema = try #require(generationConfig["responseJsonSchema"] as? [String: Any])
            #expect(schema["required"] as? [String] == ["text"])
            #expect(schema["additionalProperties"] as? Bool == false)

            return try TestHTTP.response(
                for: request,
                body: #"{"candidates":[{"content":{"parts":[{"text":"{\"text\":\"Gemini rewrite\"}"}]}}]}"#
            )
        }
        let service = GoogleRewriteService(
            apiKey: "test-key",
            model: "gemini-test",
            session: session
        )

        let text = try await service.rewrite(.cleanup("hello"))

        #expect(text == "Gemini rewrite")
    }

    @Test func anthropicRequestsSchemaAndExtractsText() async throws {
        let session = TestHTTP.makeSession { request in
            let body = try TestHTTP.jsonBody(from: request)
            let outputConfig = try #require(body["output_config"] as? [String: Any])
            let format = try #require(outputConfig["format"] as? [String: Any])
            #expect(format["type"] as? String == "json_schema")
            let schema = try #require(format["schema"] as? [String: Any])
            #expect(schema["required"] as? [String] == ["text"])
            #expect(schema["additionalProperties"] as? Bool == false)

            return try TestHTTP.response(
                for: request,
                body: #"{"content":[{"type":"text","text":"{\"text\":\"Claude rewrite\"}"}]}"#
            )
        }
        let service = AnthropicRewriteService(
            apiKey: "test-key",
            model: "claude-test",
            session: session
        )

        let text = try await service.rewrite(.cleanup("hello"))

        #expect(text == "Claude rewrite")
    }

    @Test func malformedStructuredOutputIsRejected() async {
        let session = TestHTTP.makeSession { request in
            try TestHTTP.response(
                for: request,
                body: #"{"choices":[{"message":{"content":"plain text"}}]}"#
            )
        }
        let service = OpenAIRewriteService(
            configuration: makeConfiguration(provider: .deepSeek),
            session: session
        )

        await #expect(throws: OpenAIError.invalidResponse(provider: .deepSeek)) {
            try await service.rewrite(.cleanup("hello"))
        }
    }

    private func makeConfiguration(provider: DictationProvider) -> RewriteProviderConfiguration {
        RewriteProviderConfiguration(
            provider: provider,
            model: DictationProviderDefaults.rewriteModel(for: provider),
            backend: .remote(
                OpenAICompatibleProviderEndpointConfiguration(
                    provider: provider,
                    apiKey: "sk-test",
                    baseURL: URL(string: "https://api.example.com/v1")!
                )
            )
        )
    }
}

private enum TestHTTP {
    static func makeSession(
        handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]

        let sessionID = UUID().uuidString
        var headers = configuration.httpAdditionalHeaders ?? [:]
        headers[URLProtocolStub.sessionIdentifierHeader] = sessionID
        configuration.httpAdditionalHeaders = headers
        URLProtocolStub.configure(sessionID: sessionID, handler: handler)
        return URLSession(configuration: configuration)
    }

    static func jsonBody(from request: URLRequest) throws -> [String: Any] {
        let data: Data
        if let httpBody = request.httpBody {
            data = httpBody
        } else if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }

            var streamedData = Data()
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4_096)
            defer { buffer.deallocate() }
            while stream.hasBytesAvailable {
                let count = stream.read(buffer, maxLength: 4_096)
                guard count >= 0 else {
                    throw stream.streamError ?? TestHTTPError.missingRequestBody
                }
                guard count > 0 else { break }
                streamedData.append(buffer, count: count)
            }
            data = streamedData
        } else {
            throw TestHTTPError.missingRequestBody
        }

        guard let body = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TestHTTPError.invalidRequestBody
        }
        return body
    }

    static func response(
        for request: URLRequest,
        body: String,
        statusCode: Int = 200
    ) throws -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: try #require(request.url),
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (response, Data(body.utf8))
    }
}

private enum TestHTTPError: Error {
    case missingRequestBody
    case invalidRequestBody
    case missingHandler
}

private final class URLProtocolStub: URLProtocol, @unchecked Sendable {
    static let sessionIdentifierHeader = "X-Stet-Test-Session-ID"

    private static let lock = NSLock()
    private static var handlers: [String: @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)] = [:]

    static func configure(
        sessionID: String,
        handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    ) {
        lock.lock()
        defer { lock.unlock() }
        handlers[sessionID] = handler
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lock.lock()
        let sessionID = request.value(forHTTPHeaderField: Self.sessionIdentifierHeader)
        let handler = sessionID.flatMap { Self.handlers[$0] }
        Self.lock.unlock()

        guard let handler else {
            client?.urlProtocol(self, didFailWithError: TestHTTPError.missingHandler)
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
