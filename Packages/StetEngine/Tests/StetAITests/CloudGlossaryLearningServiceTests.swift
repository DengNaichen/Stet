import Foundation
import StetAI
import StetCore
import StetRewrite
import Testing

@Suite("Cloud Glossary Learning", .serialized)
struct CloudGlossaryLearningServiceTests {
    @Test func deepSeekDisablesThinkingUsesCacheKeyAndExtractsValidatedTerm() async throws {
        let session = GlossaryTestHTTP.makeSession { request in
            let body = try GlossaryTestHTTP.jsonBody(from: request)
            #expect(request.url?.absoluteString == "https://api.deepseek.com/v1/chat/completions")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer ds-key")
            #expect(request.timeoutInterval == 10)
            #expect(body["model"] as? String == "deepseek-flash")
            #expect(body["prompt_cache_key"] as? String == GlossaryLearningPrompt.cacheAffinityKey)
            let thinking = try #require(body["thinking"] as? [String: Any])
            #expect(thinking["type"] as? String == "disabled")
            #expect(body["reasoning_effort"] == nil)

            return try GlossaryTestHTTP.response(
                for: request,
                body: #"""
                    {"id":"chat-1","object":"chat.completion","created":1,"model":"deepseek-flash","choices":[{"index":0,"message":{"role":"assistant","content":"{\"decision\":\"learn\",\"reason\":\"ASR phonetic error\",\"terms\":[\"Python\"]}"},"finish_reason":"stop"}]}
                    """#
            )
        }
        defer { session.invalidateAndCancel() }

        let config = DictationProviderConfigurationResolver.rewriteConfiguration(
            provider: .deepSeek,
            apiKey: "ds-key",
            customModel: "deepseek-flash",
            thinkingLevel: .high
        )
        #expect(config.minimumEffortForGlossaryLearning.thinkingLevel == .off)

        let service = CloudGlossaryLearningService(configuration: config, session: session)
        let terms = try await service.extractTerms(
            from: CorrectionEditPair(original: "我最近在学拍图", edited: "我最近在学 Python")
        )
        #expect(terms == ["Python"])
    }

    @Test func openAIUsesMinimalReasoningEffortAndStrictSchema() async throws {
        let session = GlossaryTestHTTP.makeSession { request in
            let body = try GlossaryTestHTTP.jsonBody(from: request)
            #expect(request.url?.absoluteString == "https://api.openai.com:443/v1/responses")
            #expect(request.timeoutInterval == 10)
            #expect(body["store"] as? Bool == false)
            #expect(body["user"] as? String == GlossaryLearningPrompt.cacheAffinityKey)
            let reasoning = try #require(body["reasoning"] as? [String: Any])
            #expect(reasoning["effort"] as? String == "minimal")
            let textConfig = try #require(body["text"] as? [String: Any])
            let format = try #require(textConfig["format"] as? [String: Any])
            #expect(format["name"] as? String == GlossaryLearningOutput.schemaName)
            #expect(format["strict"] as? Bool == true)

            return try GlossaryTestHTTP.response(
                for: request,
                body: #"""
                    {"output":[{"content":[{"type":"output_text","text":"{\"decision\":\"learn\",\"reason\":\"Product name casing\",\"terms\":[\"Herdr\"]}"}]}]}
                    """#
            )
        }
        defer { session.invalidateAndCancel() }

        let config = DictationProviderConfigurationResolver.rewriteConfiguration(
            provider: .openAI,
            apiKey: "sk-test",
            customModel: "gpt-5.6-luna",
            thinkingLevel: .high
        )
        let service = CloudGlossaryLearningService(configuration: config, session: session)
        let terms = try await service.extractTerms(
            from: CorrectionEditPair(original: "写进 herder 里", edited: "写进 Herdr 里")
        )
        #expect(terms == ["Herdr"])
    }

    @Test func googleUsesLowThinkingLevelAndDoesNotRetryFailures() async throws {
        let attempts = GlossaryCounter()
        let session = GlossaryTestHTTP.makeSession { request in
            attempts.increment()
            let body = try GlossaryTestHTTP.jsonBody(from: request)
            let genConfig = try #require(body["generationConfig"] as? [String: Any])
            let thinkingConfig = try #require(genConfig["thinkingConfig"] as? [String: Any])
            #expect(thinkingConfig["thinkingLevel"] as? String == "low")
            return try GlossaryTestHTTP.response(for: request, body: #"{"error":{"message":"busy"}}"#, statusCode: 503)
        }
        defer { session.invalidateAndCancel() }

        let config = DictationProviderConfigurationResolver.rewriteConfiguration(
            provider: .google,
            apiKey: "g-key",
            customModel: "gemini-3.8-flash",
            thinkingLevel: .high
        )
        let service = CloudGlossaryLearningService(configuration: config, session: session)
        await #expect(throws: (any Error).self) {
            _ = try await service.extractTerms(
                from: CorrectionEditPair(original: "拍图", edited: "Python")
            )
        }
        #expect(attempts.value == 1)
    }
}

private final class GlossaryCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
    func increment() {
        lock.lock()
        defer { lock.unlock() }
        count += 1
    }
}

private enum GlossaryTestHTTP {
    static func makeSession(
        handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> URLSession {
        let sessionID = UUID().uuidString
        GlossaryURLProtocolStub.configure(sessionID: sessionID, handler: handler)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GlossaryURLProtocolStub.self]
        configuration.httpAdditionalHeaders = [GlossaryURLProtocolStub.sessionHeader: sessionID]
        return URLSession(configuration: configuration)
    }

    static func jsonBody(from request: URLRequest) throws -> [String: Any] {
        let data: Data
        if let httpBody = request.httpBody {
            data = httpBody
        } else if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = Data()
            let chunkSize = 4096
            var chunk = [UInt8](repeating: 0, count: chunkSize)
            while stream.hasBytesAvailable {
                let read = stream.read(&chunk, maxLength: chunkSize)
                if read <= 0 { break }
                buffer.append(chunk, count: read)
            }
            data = buffer
        } else {
            throw URLError(.badURL)
        }
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    static func response(
        for request: URLRequest,
        body: String,
        statusCode: Int = 200
    ) throws -> (HTTPURLResponse, Data) {
        let http = HTTPURLResponse(
            url: try #require(request.url),
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (http, Data(body.utf8))
    }
}

private final class GlossaryURLProtocolStub: URLProtocol, @unchecked Sendable {
    static let sessionHeader = "X-Stet-Glossary-Test-Session"
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

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        let sessionID = request.value(forHTTPHeaderField: Self.sessionHeader)
        let handler = sessionID.flatMap { Self.handlers[$0] }
        Self.lock.unlock()

        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
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
