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
            #expect(request.url?.absoluteString == "https://api.example.com:443/v1/responses")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
            #expect(request.timeoutInterval == 60)
            #expect(body["model"] as? String == DictationProviderDefaults.rewriteModel(for: .openAI))
            #expect(body["store"] as? Bool == false)
            let textConfiguration = try #require(body["text"] as? [String: Any])
            let format = try #require(textConfiguration["format"] as? [String: Any])
            #expect(format["type"] as? String == "json_schema")
            #expect(format["name"] as? String == "rewrite_output")
            #expect(format["strict"] as? Bool == true)
            let schema = try #require(format["schema"] as? [String: Any])
            #expect(schema["required"] as? [String] == ["text"])
            #expect(schema["additionalProperties"] as? Bool == false)
            let reasoning = try #require(body["reasoning"] as? [String: Any])
            #expect(reasoning["effort"] as? String == "minimal")

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

    @Test(arguments: [401, 429, 500, 503])
    func openAIPreservesHTTPError(statusCode: Int) async {
        let session = TestHTTP.makeSession { request in
            try TestHTTP.response(
                for: request,
                body: #"{"error":{"message":"provider failure","type":"server_error","param":null,"code":null}}"#,
                statusCode: statusCode
            )
        }
        defer { session.invalidateAndCancel() }
        let service = OpenAIRewriteService(configuration: makeConfiguration(provider: .openAI), session: session)

        await #expect(throws: OpenAIError.api(provider: .openAI, statusCode: statusCode, message: "provider failure")) {
            try await service.rewrite(.cleanup("hello"))
        }
    }

    @Test func openAIRejectsInvalidJSON() async {
        let session = TestHTTP.makeSession { request in
            try TestHTTP.response(for: request, body: "not JSON")
        }
        defer { session.invalidateAndCancel() }
        let service = OpenAIRewriteService(configuration: makeConfiguration(provider: .openAI), session: session)

        await #expect(throws: OpenAIError.invalidResponse(provider: .openAI)) {
            try await service.rewrite(.cleanup("hello"))
        }
    }

    @Test func openAIRejectsEmptyRewriteText() async {
        let session = TestHTTP.makeSession { request in
            try TestHTTP.response(
                for: request,
                body: #"{"output":[{"content":[{"type":"output_text","text":"{\"text\":\"\"}"}]}]}"#
            )
        }
        defer { session.invalidateAndCancel() }
        let service = OpenAIRewriteService(configuration: makeConfiguration(provider: .openAI), session: session)

        await #expect(throws: OpenAIError.missingRewriteText) {
            try await service.rewrite(.cleanup("hello"))
        }
    }

    @Test(arguments: [URLError.timedOut, URLError.cancelled])
    func openAIPreservesTransportError(code: URLError.Code) async {
        let session = TestHTTP.makeSession { _ in throw URLError(code) }
        defer { session.invalidateAndCancel() }
        let service = OpenAIRewriteService(configuration: makeConfiguration(provider: .openAI), session: session)

        await #expect {
            try await service.rewrite(.cleanup("hello"))
        } throws: { error in
            (error as? URLError)?.code == code
        }
    }

    @Test func deepSeekRequestsJSONObjectAndExtractsText() async throws {
        let session = TestHTTP.makeSession { request in
            let body = try TestHTTP.jsonBody(from: request)
            let responseFormat = try #require(body["response_format"] as? [String: Any])
            #expect(responseFormat["type"] as? String == "json_object")
            let thinking = try #require(body["thinking"] as? [String: Any])
            #expect(thinking["type"] as? String == "disabled")
            #expect(body["reasoning_effort"] == nil)
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
            #expect(jsonSchema["name"] as? String == "rewrite_output")
            let schema = try #require(jsonSchema["schema"] as? [String: Any])
            #expect(schema["type"] as? String == "object")
            #expect(schema["required"] as? [String] == ["text"])
            #expect(schema["additionalProperties"] as? Bool == false)
            let properties = try #require(schema["properties"] as? [String: [String: String]])
            #expect(properties["text"]?["type"] == "string")

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
            let thinkingConfig = try #require(generationConfig["thinkingConfig"] as? [String: Any])
            #expect(thinkingConfig["thinkingLevel"] as? String == "low")
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

    @Test func rewriteCatalogUsesCurrentFastTierModels() {
        let expected: [(DictationProvider, String)] = [
            (.openAI, "gpt-5.6-luna"),
            (.google, "gemini-3.7-flash"),
            (.deepSeek, "deepseek-v4-flash"),
            (.qwen, "qwen3.5-flash"),
            (.glm, "glm-4.7-flash"),
        ]

        for (provider, modelID) in expected {
            #expect(RewriteModel.default(for: provider).rawValue == modelID)
            #expect(DictationProviderDefaults.rewriteModel(for: provider) == modelID)
            #expect(RewriteModel.availableModels(for: provider) == [RewriteModel.default(for: provider)])
        }

        #expect(RewriteModel.availableModels(for: .groq).isEmpty)
        #expect(RewriteModel.availableModels(for: .doubao).isEmpty)
        #expect(RewriteModel.availableModels(for: .anthropic).isEmpty)
        #expect(RewriteModel.availableModels(for: .custom).isEmpty)
        #expect(DictationProviderDefaults.rewriteModel(for: .custom).isEmpty)
    }

    @Test func customEndpointRequestsJSONObjectWithoutThinking() async throws {
        let session = TestHTTP.makeSession { request in
            #expect(request.url?.absoluteString == "http://127.0.0.1:11434/v1/chat/completions")
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            let body = try TestHTTP.jsonBody(from: request)
            #expect(body["model"] as? String == "llama3.1")
            #expect(body["thinking"] == nil)
            #expect(body["reasoning_effort"] == nil)
            let responseFormat = try #require(body["response_format"] as? [String: Any])
            #expect(responseFormat["type"] as? String == "json_object")

            return try TestHTTP.response(
                for: request,
                body: #"{"choices":[{"message":{"content":"{\"text\":\"Custom rewrite\"}"}}]}"#
            )
        }
        let service = OpenAIRewriteService(
            configuration: DictationProviderConfigurationResolver.rewriteConfiguration(
                provider: .custom,
                apiKey: "",
                customModel: "llama3.1",
                baseURL: URL(string: "http://127.0.0.1:11434/v1")!
            ),
            session: session
        )

        let text = try await service.rewrite(.cleanup("hello"))

        #expect(text == "Custom rewrite")
    }

    @Test func customModelProbeListsModelsWithoutRequiringAPIKey() async throws {
        let session = TestHTTP.makeSession { request in
            #expect(request.httpMethod == "GET")
            #expect(request.url?.absoluteString == "https://openrouter.ai/api/v1/models")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-live")

            return try TestHTTP.response(
                for: request,
                body: #"{"data":[{"id":"openrouter/auto"},{"id":"gpt-4o-mini"}]}"#
            )
        }
        let probe = OpenAICompatibleModelProbe(session: session)

        let models = try await probe.listModels(
            baseURL: URL(string: "https://openrouter.ai/api/v1")!,
            apiKey: "sk-live"
        )

        #expect(models == ["gpt-4o-mini", "openrouter/auto"])
    }

    @Test(arguments: [
        (DictationProvider.groq, "https://api.groq.com/openai/v1/chat/completions"),
        (.deepSeek, "https://api.deepseek.com/v1/chat/completions"),
        (.qwen, "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"),
        (.glm, "https://open.bigmodel.cn/api/paas/v4/chat/completions"),
        (.doubao, "https://ark.cn-beijing.volces.com/api/v3/chat/completions"),
    ])
    func compatibleProviderRequests(provider: DictationProvider, url: String) async throws {
        let session = TestHTTP.makeSession { request in
            #expect(request.url?.absoluteString == url)
            #expect(request.httpMethod == "POST")
            #expect(request.timeoutInterval == 60)
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer key")
            #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
            let body = try TestHTTP.jsonBody(from: request)
            #expect(body["model"] as? String == "override-model")
            let messages = try #require(body["messages"] as? [[String: Any]])
            #expect(messages.count == 2)
            #expect(messages.first?["role"] as? String == "system")
            #expect(messages.last?["role"] as? String == "user")
            #expect((body["response_format"] as? [String: Any])?["type"] as? String == "json_object")
            #expect(body["reasoning_effort"] == nil)
            if provider != .deepSeek { #expect(body["thinking"] == nil) }
            return try TestHTTP.response(for: request, body: Self.standardChatResponse)
        }
        let configuration = DictationProviderConfigurationResolver.rewriteConfiguration(
            provider: provider, apiKey: " key "
        )
        let service = OpenAIRewriteService(configuration: configuration, session: session)
        #expect(try await service.rewrite(.init(text: "hello", model: "override-model")) == "OK")
    }

    @Test(arguments: [nil, .off, .minimal, .low, .medium, .high, .max] as [RewriteThinkingLevel?])
    func deepSeekThinkingLevels(level: RewriteThinkingLevel?) async throws {
        let session = TestHTTP.makeSession { request in
            let body = try TestHTTP.jsonBody(from: request)
            let thinking = try #require(body["thinking"] as? [String: Any])
            #expect(thinking["type"] as? String == (level == .off ? "disabled" : "enabled"))
            let effort: String? =
                switch level {
                case .low: "low"
                case .high: "high"
                case .max: "max"
                default: nil
                }
            #expect(body["reasoning_effort"] as? String == effort)
            return try TestHTTP.response(for: request, body: Self.standardChatResponse)
        }
        let configuration = DictationProviderConfigurationResolver.rewriteConfiguration(
            provider: .deepSeek, apiKey: "key", thinkingLevel: level
        )
        #expect(
            try await OpenAIRewriteService(configuration: configuration, session: session)
                .rewrite(.cleanup("hello")) == "OK")
    }

    @Test(
        arguments: [
            "http://localhost:11434/nested/v1", "http://localhost:11434/nested/v1/",
            "https://example.com/v1", "https://example.com:443/v1", "http://localhost/v1",
        ],
        ["", "  ", " key "])
    func customURLAndAuthentication(baseURL: String, key: String) async throws {
        let expectedURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/chat/completions"
        let session = TestHTTP.makeSession { request in
            #expect(request.url?.absoluteString == expectedURL)
            #expect(request.value(forHTTPHeaderField: "Authorization") == (key == " key " ? "Bearer key" : nil))
            return try TestHTTP.response(for: request, body: Self.standardChatResponse)
        }
        let configuration = DictationProviderConfigurationResolver.rewriteConfiguration(
            provider: .custom, apiKey: key, customModel: "local", baseURL: URL(string: baseURL)!
        )
        #expect(
            try await OpenAIRewriteService(configuration: configuration, session: session)
                .rewrite(.cleanup("hello")) == "OK")
    }

    @Test func customEndpointPreservesEncodedPathAndQuery() async throws {
        let session = TestHTTP.makeSession { request in
            #expect(request.url?.absoluteString == "https://example.com/proxy%20name/v1/chat/completions?tenant=one")
            #expect(request.value(forHTTPHeaderField: "OpenAI-Organization") == nil)
            #expect(request.value(forHTTPHeaderField: "OpenAI-Project") == nil)
            return try TestHTTP.response(for: request, body: Self.standardChatResponse)
        }
        let endpoint = OpenAICompatibleProviderEndpointConfiguration(
            provider: .custom, apiKey: "key",
            baseURL: URL(string: "https://example.com/proxy%20name/v1?tenant=one")!,
            organizationID: "openai-org", projectID: "openai-project"
        )
        let configuration = RewriteProviderConfiguration(provider: .custom, model: "local", backend: .remote(endpoint))
        #expect(
            try await OpenAIRewriteService(configuration: configuration, session: session)
                .rewrite(.cleanup("hello")) == "OK")
    }

    @Test(arguments: [DictationProvider.groq, .deepSeek, .qwen, .glm, .doubao, .openAI])
    func missingKeyDoesNotSendRequest(provider: DictationProvider) async {
        let session = TestHTTP.makeSession { request in
            Issue.record("Missing key must fail before transport")
            return try TestHTTP.response(for: request, body: Self.standardChatResponse)
        }
        let configuration = DictationProviderConfigurationResolver.rewriteConfiguration(
            provider: provider, apiKey: "  ")
        await #expect(throws: OpenAIError.missingAPIKey(provider: provider)) {
            try await OpenAIRewriteService(configuration: configuration, session: session).rewrite(.cleanup("hello"))
        }
    }

    @Test(
        arguments: [401, 429, 500, 503],
        [
            #"{"error":{"message":"  rejected  "}}"#,
            #"{"error":{"message":"  rejected  ","type":"api_error","code":42}}"#,
            #"{"error":{"message":"  rejected  ","type":"api_error","code":"bad"}}"#,
            #"{"error":{"message":"  "}}"#,
            "not JSON",
            standardChatResponse,
        ])
    func chatErrorsPreserveStatusAndMessage(status: Int, body: String) async {
        let session = TestHTTP.makeSession { request in
            try TestHTTP.response(for: request, body: body, statusCode: status)
        }
        let expectedMessage =
            body.contains("rejected") ? "rejected" : HTTPURLResponse.localizedString(forStatusCode: status)
        await #expect(throws: OpenAIError.api(provider: .deepSeek, statusCode: status, message: expectedMessage)) {
            try await OpenAIRewriteService(configuration: makeConfiguration(provider: .deepSeek), session: session)
                .rewrite(.cleanup("hello"))
        }
    }

    @Test(arguments: [
        "not JSON", "{}", #"{"choices":[{}]}"#,
        #"{"choices":[{"message":{"content":42}}]}"#,
        #"{"choices":[{"message":{"content":"{\"text\":\"OK\"}"}},{"message":null}]}"#,
        #"{"choices":[{"message":{"content":"invalid structured output"}}]}"#,
        #"{"error":{"message":"error in 200","type":"api_error"}}"#,
    ])
    func invalidChatResponse(body: String) async {
        let session = TestHTTP.makeSession { request in try TestHTTP.response(for: request, body: body) }
        await #expect(throws: OpenAIError.invalidResponse(provider: .deepSeek)) {
            try await OpenAIRewriteService(configuration: makeConfiguration(provider: .deepSeek), session: session)
                .rewrite(.cleanup("hello"))
        }
    }

    @Test(arguments: [
        #"{"choices":[]}"#, #"{"choices":[{"message":{}}]}"#,
        #"{"choices":[{"message":{"content":null}}]}"#,
        #"{"choices":[{"message":{"content":"  "}}]}"#,
        #"{"choices":[{"message":{"content":"{\"text\":\"  \"}"}}]}"#,
    ])
    func emptyChatResponse(body: String) async {
        let session = TestHTTP.makeSession { request in try TestHTTP.response(for: request, body: body) }
        await #expect(throws: OpenAIError.missingRewriteText) {
            try await OpenAIRewriteService(configuration: makeConfiguration(provider: .deepSeek), session: session)
                .rewrite(.cleanup("hello"))
        }
    }

    @Test(arguments: [
        #"{"choices":[{"message":{"content":null}},{"message":{"content":"  "}},{"message":{"content":"{\"text\":\"OK\"}"}}]}"#,
        #"{"created":1,"choices":[{"index":0,"message":{"content":"{\"text\":\"OK\"}"}}]}"#,
    ])
    func partialChatResponsesPreserveFirstNonemptyText(body: String) async throws {
        let calls = RequestCounter()
        let session = TestHTTP.makeSession { request in
            calls.increment()
            return try TestHTTP.response(for: request, body: body)
        }
        #expect(
            try await OpenAIRewriteService(configuration: makeConfiguration(provider: .deepSeek), session: session)
                .rewrite(.cleanup("hello")) == "OK")
        #expect(calls.value == 1)
    }

    @Test(arguments: [URLError.timedOut, URLError.cancelled])
    func chatTransportErrorsAreNotRetried(code: URLError.Code) async {
        let calls = RequestCounter()
        let session = TestHTTP.makeSession { _ in
            calls.increment()
            throw URLError(code)
        }
        do {
            _ = try await OpenAIRewriteService(configuration: makeConfiguration(provider: .deepSeek), session: session)
                .rewrite(.cleanup("hello"))
            Issue.record("Expected transport failure")
        } catch {
            #expect((error as? URLError)?.code == code)
        }
        #expect(calls.value == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func cancellingChatStopsTheUnderlyingRequest() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PendingChatURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let service = OpenAIRewriteService(configuration: makeConfiguration(provider: .deepSeek), session: session)
        let task = Task { try await service.rewrite(.cleanup("hello")) }
        var events = PendingChatURLProtocol.events.makeAsyncIterator()
        #expect(await events.next() == "started")
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("Cancelled request must fail")
        } catch {
            #expect((error as? URLError)?.code == .cancelled || error is CancellationError)
        }
        #expect(await events.next() == "stopped")
        #expect(PendingChatURLProtocol.requests.value == 1)
    }

    @Test func cloudServicesPrewarmConnectionOnSharedSessionAndIgnoreFailures() async throws {
        let seenPaths = RequestRecorder()
        let session = TestHTTP.makeSession { request in
            seenPaths.record("\(request.httpMethod ?? "") \(request.url?.absoluteString ?? "")")
            if request.url?.path.hasSuffix("/models") == true {
                #expect(request.httpMethod == "GET")
                #expect(request.timeoutInterval == 10)
                return try TestHTTP.response(for: request, body: #"{"error":{"message":"ignored"}}"#, statusCode: 503)
            }
            return try TestHTTP.response(for: request, body: Self.standardChatResponse)
        }
        defer { session.invalidateAndCancel() }

        let deepSeek = OpenAIRewriteService(configuration: makeConfiguration(provider: .deepSeek), session: session)
        await deepSeek.prewarm(.cleanup(""))
        #expect(try await deepSeek.rewrite(.cleanup("hello")) == "OK")

        let google = GoogleRewriteService(apiKey: " g-key ", model: "gemini-test", session: session)
        await google.prewarm(.cleanup(""))

        let anthropic = AnthropicRewriteService(apiKey: " a-key ", model: "claude-test", session: session)
        await anthropic.prewarm(.cleanup(""))

        let missingKey = OpenAIRewriteService(
            configuration: DictationProviderConfigurationResolver.rewriteConfiguration(
                provider: .deepSeek,
                apiKey: " "
            ),
            session: session
        )
        await missingKey.prewarm(.cleanup(""))

        #expect(
            seenPaths.values == [
                "GET https://api.example.com/v1/models",
                "POST https://api.example.com/v1/chat/completions",
                "GET https://generativelanguage.googleapis.com/v1beta/models?key=g-key",
                "GET https://api.anthropic.com/v1/models",
            ]
        )
    }

    private static let standardChatResponse =
        #"{"id":"chat-test","object":"chat.completion","created":1,"model":"test","choices":[{"index":0,"finish_reason":"stop","message":{"role":"assistant","content":"{\"text\":\"OK\"}"}}]}"#

    private func makeConfiguration(provider: DictationProvider) -> RewriteProviderConfiguration {
        let thinkingLevel: RewriteThinkingLevel? =
            switch provider {
            case .openAI: .minimal
            case .deepSeek: .off
            default: nil
            }
        return RewriteProviderConfiguration(
            provider: provider,
            model: DictationProviderDefaults.rewriteModel(for: provider),
            backend: .remote(
                OpenAICompatibleProviderEndpointConfiguration(
                    provider: provider,
                    apiKey: "sk-test",
                    baseURL: URL(string: "https://api.example.com/v1")!
                )
            ),
            thinkingLevel: thinkingLevel
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

private final class RequestCounter: @unchecked Sendable {
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

private final class RequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String] = []
    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }
    func record(_ entry: String) {
        lock.lock()
        defer { lock.unlock() }
        entries.append(entry)
    }
}

/// Deliberately leaves the URL load pending until the owning task cancels it.
private final class PendingChatURLProtocol: URLProtocol, @unchecked Sendable {
    static let requests = RequestCounter()
    private static let channel = AsyncStream<String>.makeStream()
    static var events: AsyncStream<String> { channel.stream }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.increment()
        Self.channel.continuation.yield("started")
    }
    override func stopLoading() {
        Self.channel.continuation.yield("stopped")
    }
}
