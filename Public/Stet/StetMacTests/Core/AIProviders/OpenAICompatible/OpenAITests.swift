import Foundation
import OpenAI
import StetCore
import StetRewrite
import Testing

@testable import Stet
@testable import StetAI

@MainActor
@Suite("OpenAI Adapters", .serialized)
struct OpenAITests {
    private func makeEndpoint(
        provider: DictationProvider = .openAI,
        apiKey: String = "sk-test",
        baseURL: URL = URL(string: "https://api.example.com/v1")!,
        organizationID: String? = nil,
        projectID: String? = nil
    ) -> OpenAICompatibleProviderEndpointConfiguration {
        OpenAICompatibleProviderEndpointConfiguration(
            provider: provider,
            apiKey: apiKey,
            baseURL: baseURL,
            organizationID: organizationID,
            projectID: projectID
        )
    }

    private func makeRewriteConfiguration(
        provider: DictationProvider = .openAI,
        apiKey: String = "sk-test",
        baseURL: URL = URL(string: "https://api.example.com/v1")!
    ) -> RewriteProviderConfiguration {
        RewriteProviderConfiguration(
            provider: provider,
            model: DictationProviderDefaults.rewriteModel(for: provider),
            backend: .remote(makeEndpoint(provider: provider, apiKey: apiKey, baseURL: baseURL))
        )
    }

    @Test func openAICompatibleEndpointBuildsSDKConfigurationFromBaseURL() throws {
        let configuration = makeEndpoint(
            organizationID: "org_123",
            projectID: "proj_123"
        )
        let sdkConfiguration = try configuration.sdkConfiguration(additionalHeaders: ["X-Test": "1"])

        #expect(sdkConfiguration.token == "sk-test")
        #expect(sdkConfiguration.organizationIdentifier == "org_123")
        #expect(sdkConfiguration.host == "api.example.com")
        #expect(sdkConfiguration.basePath == "/v1/")
        #expect(sdkConfiguration.customHeaders["OpenAI-Project"] == "proj_123")
        #expect(sdkConfiguration.customHeaders["X-Test"] == "1")
    }

    @Test func openAIRewriteServiceUsesFallbackOutputParsing() async throws {
        let session = TestURLSessionFactory.makeSession { request in
            let body =
                try JSONSerialization.jsonObject(with: TestSupport.requestBodyData(from: request)) as? [String: Any]
            let input = try #require(body?["input"] as? [[String: Any]])
            #expect((input.first?["role"] as? String) == "system")
            #expect((input.last?["content"] as? String)?.contains("Instruction:") == true)
            let textConfiguration = try #require(body?["text"] as? [String: Any])
            let format = try #require(textConfiguration["format"] as? [String: Any])
            #expect(format["type"] as? String == "json_schema")
            #expect(format["name"] as? String == "rewrite_output")
            #expect(format["strict"] as? Bool == true)
            let schema = try #require(format["schema"] as? [String: Any])
            #expect(schema["required"] as? [String] == ["text"])
            #expect(schema["additionalProperties"] as? Bool == false)

            let response = HTTPURLResponse(
                url: try #require(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = Data(
                """
                {
                  "created_at": 123,
                  "error": null,
                  "id": "resp-1",
                  "incomplete_details": null,
                  "instructions": null,
                  "max_output_tokens": null,
                  "metadata": {},
                  "model": "test-model",
                  "object": "response",
                  "output": [
                    {
                      "id": "msg-1",
                      "type": "message",
                      "role": "assistant",
                      "content": [
                        {
                          "type": "output_text",
                          "text": "{\\\"text\\\":\\\"rewritten\\\"}",
                          "annotations": [],
                          "logprobs": []
                        }
                      ],
                      "status": "completed"
                    }
                  ],
                  "parallel_tool_calls": false,
                  "previous_response_id": null,
                  "reasoning": null,
                  "status": "completed",
                  "temperature": null,
                  "text": {
                    "format": {
                      "type": "text"
                    }
                  },
                  "tool_choice": "auto",
                  "tools": [],
                  "top_p": null,
                  "truncation": null,
                  "usage": null,
                  "user": null
                }
                """.utf8
            )
            return (response, data)
        }
        let service = OpenAIRewriteService(
            configuration: makeRewriteConfiguration(),
            session: session
        )

        let text = try await service.rewrite(
            .cleanup(
                "hello",
                audience: .human,
                preferredSpellings: ["OpenAI"]
            )
        )

        #expect(text == "rewritten")
    }

    @Test func openAIRewriteServiceMapsProviderErrors() async {
        let session = TestURLSessionFactory.makeSession { request in
            let response = HTTPURLResponse(
                url: try #require(request.url), statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (
                response,
                Data(#"{"error":{"message":"bad key","type":"invalid_request_error","param":null,"code":null}}"#.utf8)
            )
        }
        let service = OpenAIRewriteService(
            configuration: makeRewriteConfiguration(),
            session: session
        )

        await #expect(throws: OpenAIError.api(provider: .openAI, statusCode: 401, message: "bad key")) {
            try await service.rewrite(.cleanup("hello"))
        }
    }

    @Test func openAIRewriteServiceRecoversTextFromRawResponseWhenSDKDecodingFails() async throws {
        let session = TestURLSessionFactory.makeSession { request in
            let response = HTTPURLResponse(
                url: try #require(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = Data(
                """
                {
                  "created_at": 123,
                  "error": null,
                  "id": "resp-1",
                  "incomplete_details": null,
                  "instructions": null,
                  "max_output_tokens": null,
                  "metadata": {},
                  "model": "test-model",
                  "object": "response",
                  "output": [
                    {
                      "id": "reasoning-1",
                      "type": "reasoning_mystery",
                      "content": []
                    },
                    {
                      "id": "msg-1",
                      "type": "message",
                      "role": "assistant",
                      "content": [
                        {
                          "type": "output_text",
                          "text": "{\\\"text\\\":\\\"recovered rewrite\\\"}",
                          "annotations": [],
                          "logprobs": []
                        }
                      ],
                      "status": "completed"
                    }
                  ],
                  "parallel_tool_calls": false,
                  "previous_response_id": null,
                  "reasoning": null,
                  "status": "completed",
                  "temperature": null,
                  "text": {
                    "format": {
                      "type": "text"
                    }
                  },
                  "tool_choice": "auto",
                  "tools": [],
                  "top_p": null,
                  "truncation": null,
                  "usage": null,
                  "user": null
                }
                """.utf8
            )
            return (response, data)
        }
        let service = OpenAIRewriteService(
            configuration: makeRewriteConfiguration(),
            session: session
        )

        let text = try await service.rewrite(
            .cleanup("hello")
        )

        #expect(text == "recovered rewrite")
    }

    @Test func openAICompatibleChineseProviderUsesChatCompletionsEndpoint() async throws {
        let session = TestURLSessionFactory.makeSession { request in
            #expect(request.url?.absoluteString == "https://api.deepseek.com/v1/chat/completions")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")

            let body =
                try JSONSerialization.jsonObject(with: TestSupport.requestBodyData(from: request)) as? [String: Any]
            #expect(body?["model"] as? String == "deepseek-v4-flash")
            let thinking = try #require(body?["thinking"] as? [String: Any])
            #expect(thinking["type"] as? String == "disabled")
            let responseFormat = try #require(body?["response_format"] as? [String: Any])
            #expect(responseFormat["type"] as? String == "json_object")
            let messages = try #require(body?["messages"] as? [[String: Any]])
            #expect(messages.count == 2)
            #expect(messages.first?["role"] as? String == "system")
            #expect(messages.last?["role"] as? String == "user")
            #expect((messages.last?["content"] as? String)?.contains("Instruction:") == true)

            let response = HTTPURLResponse(
                url: try #require(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (
                response,
                Data(
                    """
                    {
                      "id": "chatcmpl-test",
                      "object": "chat.completion",
                      "choices": [
                        {
                          "index": 0,
                          "message": {
                            "role": "assistant",
                            "content": "{\\\"text\\\":\\\"rewritten from chat completions\\\"}"
                          },
                          "finish_reason": "stop"
                        }
                      ]
                    }
                    """.utf8
                )
            )
        }
        let service = OpenAIRewriteService(
            configuration: makeRewriteConfiguration(
                provider: .deepSeek,
                baseURL: URL(string: "https://api.deepseek.com/v1")!
            ),
            session: session
        )

        let text = try await service.rewrite(.cleanup("hello"))

        #expect(text == "rewritten from chat completions")
    }

    @Test func groqGPTOSSUsesStrictJSONSchema() async throws {
        let session = TestURLSessionFactory.makeSession { request in
            let body =
                try JSONSerialization.jsonObject(with: TestSupport.requestBodyData(from: request)) as? [String: Any]
            let responseFormat = try #require(body?["response_format"] as? [String: Any])
            #expect(responseFormat["type"] as? String == "json_schema")
            let jsonSchema = try #require(responseFormat["json_schema"] as? [String: Any])
            #expect(jsonSchema["name"] as? String == "rewrite_output")
            #expect(jsonSchema["strict"] as? Bool == true)
            let schema = try #require(jsonSchema["schema"] as? [String: Any])
            #expect(schema["required"] as? [String] == ["text"])
            #expect(schema["additionalProperties"] as? Bool == false)

            let response = HTTPURLResponse(
                url: try #require(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (
                response,
                Data(
                    #"{"choices":[{"message":{"content":"{\"text\":\"Groq rewrite\"}"}}]}"#.utf8
                )
            )
        }
        let service = OpenAIRewriteService(
            configuration: makeRewriteConfiguration(
                provider: .groq,
                baseURL: URL(string: "https://api.groq.com/openai/v1")!
            ),
            session: session
        )

        let text = try await service.rewrite(.cleanup("hello"))

        #expect(text == "Groq rewrite")
    }

    @Test func cloudRewriteRejectsMalformedStructuredOutput() async {
        let session = TestURLSessionFactory.makeSession { request in
            let response = HTTPURLResponse(
                url: try #require(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (
                response,
                Data(#"{"choices":[{"message":{"content":"plain text"}}]}"#.utf8)
            )
        }
        let service = OpenAIRewriteService(
            configuration: makeRewriteConfiguration(
                provider: .deepSeek,
                baseURL: URL(string: "https://api.deepseek.com/v1")!
            ),
            session: session
        )

        await #expect(throws: OpenAIError.invalidResponse(provider: .deepSeek)) {
            try await service.rewrite(.cleanup("hello"))
        }
    }

    @Test func openAICompatibleChineseProviderMapsChatCompletionsErrors() async {
        let session = TestURLSessionFactory.makeSession { request in
            let response = HTTPURLResponse(
                url: try #require(request.url), statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (
                response,
                Data(#"{"error":{"message":"invalid deepseek key"}}"#.utf8)
            )
        }
        let service = OpenAIRewriteService(
            configuration: makeRewriteConfiguration(
                provider: .deepSeek,
                baseURL: URL(string: "https://api.deepseek.com/v1")!
            ),
            session: session
        )

        await #expect(throws: OpenAIError.api(provider: .deepSeek, statusCode: 401, message: "invalid deepseek key")) {
            try await service.rewrite(.cleanup("hello"))
        }
    }
}
