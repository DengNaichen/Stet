import Foundation
import StetRewrite
import Testing

@testable import StetAI

@MainActor
@Suite("Structured Rewrite Services", .serialized)
struct StructuredRewriteServiceTests {
    @Test func googleRequestsSchemaAndExtractsText() async throws {
        let session = TestURLSessionFactory.makeSession { request in
            let body =
                try JSONSerialization.jsonObject(with: TestSupport.requestBodyData(from: request)) as? [String: Any]
            let generationConfig = try #require(body?["generationConfig"] as? [String: Any])
            #expect(generationConfig["responseMimeType"] as? String == "application/json")
            let schema = try #require(generationConfig["responseJsonSchema"] as? [String: Any])
            #expect(schema["required"] as? [String] == ["text"])
            #expect(schema["additionalProperties"] as? Bool == false)

            let response = HTTPURLResponse(
                url: try #require(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (
                response,
                Data(
                    #"{"candidates":[{"content":{"parts":[{"text":"{\"text\":\"Gemini rewrite\"}"}]}}]}"#.utf8
                )
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
        let session = TestURLSessionFactory.makeSession { request in
            let body =
                try JSONSerialization.jsonObject(with: TestSupport.requestBodyData(from: request)) as? [String: Any]
            let outputConfig = try #require(body?["output_config"] as? [String: Any])
            let format = try #require(outputConfig["format"] as? [String: Any])
            #expect(format["type"] as? String == "json_schema")
            let schema = try #require(format["schema"] as? [String: Any])
            #expect(schema["required"] as? [String] == ["text"])
            #expect(schema["additionalProperties"] as? Bool == false)

            let response = HTTPURLResponse(
                url: try #require(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (
                response,
                Data(
                    #"{"content":[{"type":"text","text":"{\"text\":\"Claude rewrite\"}"}]}"#.utf8
                )
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

    @Test func googleRejectsMalformedStructuredOutputWithoutRetrying() async {
        var requestCount = 0
        let session = TestURLSessionFactory.makeSession { request in
            requestCount += 1
            let response = HTTPURLResponse(
                url: try #require(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (
                response,
                Data(#"{"candidates":[{"content":{"parts":[{"text":"plain text"}]}}]}"#.utf8)
            )
        }
        let service = GoogleRewriteService(
            apiKey: "test-key",
            model: "gemini-test",
            session: session
        )

        await #expect(throws: GoogleError.invalidStructuredOutput) {
            try await service.rewrite(.cleanup("hello"))
        }
        #expect(requestCount == 1)
    }
}
