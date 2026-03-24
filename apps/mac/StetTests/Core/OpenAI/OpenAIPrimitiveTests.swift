import Foundation
import OpenAI
import Testing

@testable import Stet

@Suite("OpenAI Primitives")
struct OpenAIPrimitiveTests {
    @Test func errorMapperPassesThroughExistingOpenAIError() {
        let error = Stet.OpenAIError.missingAPIKey(provider: .groq)

        let mapped = OpenAISDKErrorMapper.map(error, responseStatusCode: 401, provider: .openAI)

        #expect(mapped as? Stet.OpenAIError == .missingAPIKey(provider: .groq))
    }

    @Test func errorMapperConvertsAPIErrorResponseIntoProviderAwareAPIError() throws {
        let response = try JSONDecoder().decode(
            APIErrorResponse.self,
            from: Data(#"{"error":{"message":"bad key","type":"invalid_request_error","param":null,"code":null}}"#.utf8)
        )

        let mapped = OpenAISDKErrorMapper.map(response, responseStatusCode: 401, provider: .groq)

        #expect(mapped as? Stet.OpenAIError == .api(provider: .groq, statusCode: 401, message: "bad key"))
    }

    @Test func errorMapperUsesHTTPStatusMessageForDecodingFailuresOnErrorResponses() {
        let mapped = OpenAISDKErrorMapper.map(
            DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "bad payload")),
            responseStatusCode: 429,
            provider: .openAI
        )

        #expect(
            mapped as? Stet.OpenAIError
                == .api(
                    provider: .openAI, statusCode: 429, message: HTTPURLResponse.localizedString(forStatusCode: 429))
        )
    }

    @Test func errorMapperTreatsDecodingFailuresWithoutErrorStatusAsInvalidResponse() {
        let mapped = OpenAISDKErrorMapper.map(
            DecodingError.keyNotFound(
                DynamicCodingKey("text"),
                .init(codingPath: [], debugDescription: "missing")
            ),
            responseStatusCode: 200,
            provider: .groq
        )

        #expect(mapped as? Stet.OpenAIError == .invalidResponse(provider: .groq))
    }

    @Test func stetOutputTextReturnsFirstTrimmedNonEmptyAssistantText() throws {
        let response = try JSONDecoder().decode(
            ResponseObject.self,
            from: Data(
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
                          "text": "   ",
                          "annotations": [],
                          "logprobs": []
                        }
                      ],
                      "status": "completed"
                    },
                    {
                      "id": "msg-2",
                      "type": "message",
                      "role": "assistant",
                      "content": [
                        {
                          "type": "output_text",
                          "text": "  rewritten text  ",
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
            ))

        #expect(response.stetOutputText == "rewritten text")
    }

    @Test func stetOutputTextReturnsNilWhenNoOutputTextExists() throws {
        let response = try JSONDecoder().decode(
            ResponseObject.self,
            from: Data(
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
                  "output": [],
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
            ))

        #expect(response.stetOutputText == nil)
    }

    @Test func responseRecorderCapturesLatestHTTPResponseData() {
        let recorder = OpenAIHTTPResponseRecorder()
        let firstURL = URL(string: "https://example.com/first")!
        let secondURL = URL(string: "https://example.com/second")!

        recorder.record(
            HTTPURLResponse(url: firstURL, statusCode: 202, httpVersion: nil, headerFields: nil),
            data: Data("first".utf8)
        )
        recorder.record(
            HTTPURLResponse(url: secondURL, statusCode: 429, httpVersion: nil, headerFields: nil),
            data: Data("second".utf8)
        )

        #expect(recorder.statusCode == 429)
        #expect(recorder.data == Data("second".utf8))
    }

    @Test func responseRecordingMiddlewareRecordsAndPassesThroughResponse() {
        let recorder = OpenAIHTTPResponseRecorder()
        let middleware = OpenAIResponseRecordingMiddleware(responseRecorder: recorder)
        let request = URLRequest(url: URL(string: "https://example.com/request")!)
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com/request")!,
            statusCode: 204,
            httpVersion: nil,
            headerFields: nil
        )!
        let body = Data("payload".utf8)

        let intercepted = middleware.intercept(response: response, request: request, data: body)

        #expect((intercepted.response as? HTTPURLResponse)?.statusCode == 204)
        #expect(intercepted.data == body)
        #expect(recorder.statusCode == 204)
        #expect(recorder.data == body)
    }
}

private struct DynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init(_ stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(stringValue: String) {
        self.init(stringValue)
    }

    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}
