import Foundation
import OpenAI
import Testing

@testable import Stet

private final class RequestAttemptCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return count
    }

    func value() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}

@MainActor
@Suite("OpenAI Adapters", .serialized)
struct OpenAITests {
    @Test func openAIConfigurationBuildsSDKConfigurationFromBaseURL() throws {
        let configuration = OpenAIConfiguration(
            apiKey: "sk-test",
            baseURL: URL(string: "https://api.example.com/v1")!,
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

    @Test func openAITranscriptionServiceSendsMultipartFields() async throws {
        let fileURL = TestSupport.temporaryFileURL(ext: "m4a")
        try Data("audio-bytes".utf8).write(to: fileURL)
        let session = TestURLSessionFactory.makeSession { request in
            let body = String(data: try TestSupport.requestBodyData(from: request), encoding: .utf8) ?? ""
            let requestURL = try #require(request.url)
            let requestComponents = try #require(URLComponents(url: requestURL, resolvingAgainstBaseURL: false))
            #expect(requestComponents.scheme == "https")
            #expect(requestComponents.host == "api.example.com")
            #expect(requestComponents.port == 443)
            #expect(requestComponents.path == "/v1/audio/transcriptions")
            #expect((request.value(forHTTPHeaderField: "Content-Type") ?? "").contains("multipart/form-data"))
            #expect(body.contains("name=\"model\""))
            #expect(body.contains("gpt-4o-mini-transcribe"))
            #expect(request.value(forHTTPHeaderField: "X-Stet-Audio-Duration-Seconds") == "3")
            #expect(body.contains("name=\"language\""))
            #expect(body.contains("de"))
            #expect(body.contains("name=\"prompt\""))
            #expect(body.contains("Use OpenAI"))
            #expect(body.contains("filename=\"speech.m4a\""))
            #expect(!body.contains("name=\"stream\""))

            let response = HTTPURLResponse(url: requestURL, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"text":"hello"}"#.utf8))
        }
        let service = OpenAITranscriptionService(
            configuration: OpenAIConfiguration(apiKey: "sk-test", baseURL: URL(string: "https://api.example.com/v1")!),
            session: session
        )

        defer {
            try? FileManager.default.removeItem(at: fileURL)
        }

        let text = try await service.transcribe(
            audioFileAt: fileURL,
            languageCode: "de",
            prompt: "Use OpenAI",
            audioDurationSeconds: 2.4
        )
        #expect(text == "hello")
    }

    @Test func openAITranscriptionServiceMapsAPIErrorBody() async throws {
        let fileURL = TestSupport.temporaryFileURL(ext: "wav")
        try Data("audio-bytes".utf8).write(to: fileURL)
        let session = TestURLSessionFactory.makeSession { request in
            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 400,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(#"{"error":{"message":"unknown param `stream`"}}"#.utf8))
        }
        let service = OpenAITranscriptionService(
            configuration: OpenAIConfiguration(apiKey: "sk-test", baseURL: URL(string: "https://api.example.com/v1")!),
            session: session
        )

        defer {
            try? FileManager.default.removeItem(at: fileURL)
        }

        await #expect(throws: OpenAIError.api(provider: .openAI, statusCode: 400, message: "unknown param `stream`")) {
            try await service.transcribe(
                audioFileAt: fileURL,
                languageCode: nil,
                prompt: nil,
                audioDurationSeconds: 1.2
            )
        }
    }

    @Test func openAITranscriptionServiceThrowsWhenTextIsMissing() async throws {
        let fileURL = TestSupport.temporaryFileURL(ext: "wav")
        try Data("audio-bytes".utf8).write(to: fileURL)
        let session = TestURLSessionFactory.makeSession { request in
            let response = HTTPURLResponse(url: try #require(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"text":"   "}"#.utf8))
        }
        let service = OpenAITranscriptionService(
            configuration: OpenAIConfiguration(apiKey: "sk-test", baseURL: URL(string: "https://api.example.com/v1")!),
            session: session
        )

        defer {
            try? FileManager.default.removeItem(at: fileURL)
        }

        await #expect(throws: OpenAIError.missingTranscriptionText) {
            try await service.transcribe(
                audioFileAt: fileURL,
                languageCode: nil,
                prompt: nil,
                audioDurationSeconds: nil
            )
        }
    }

    @Test func openAITranscriptionServiceFallsBackToPlainTextBodyWhenSDKDecodingFails() async throws {
        let fileURL = TestSupport.temporaryFileURL(ext: "wav")
        try Data("audio-bytes".utf8).write(to: fileURL)
        let session = TestURLSessionFactory.makeSession { request in
            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/plain"]
            )!
            return (response, Data("  recovered via fallback  ".utf8))
        }
        let service = OpenAITranscriptionService(
            configuration: OpenAIConfiguration(apiKey: "sk-test", baseURL: URL(string: "https://api.example.com/v1")!),
            session: session
        )

        defer {
            try? FileManager.default.removeItem(at: fileURL)
        }

        let text = try await service.transcribe(
            audioFileAt: fileURL,
            languageCode: nil,
            prompt: nil,
            audioDurationSeconds: nil
        )

        #expect(text == "recovered via fallback")
    }

    @Test func openAITranscriptionServiceRetriesTransientFailures() async throws {
        let fileURL = TestSupport.temporaryFileURL(ext: "wav")
        try Data("audio-bytes".utf8).write(to: fileURL)
        let attempts = RequestAttemptCounter()
        let session = TestURLSessionFactory.makeSession { request in
            let attempt = attempts.increment()

            if attempt == 1 {
                let response = HTTPURLResponse(
                    url: try #require(request.url),
                    statusCode: 503,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                return (response, Data(#"{"error":{"message":"try again later","type":"server_error","param":null,"code":null}}"#.utf8))
            }

            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(#"{"text":"retried successfully"}"#.utf8))
        }
        let service = OpenAITranscriptionService(
            configuration: OpenAIConfiguration(apiKey: "sk-test", baseURL: URL(string: "https://api.example.com/v1")!),
            session: session
        )
        defer {
            try? FileManager.default.removeItem(at: fileURL)
        }

        let text = try await service.transcribe(
            audioFileAt: fileURL,
            languageCode: nil,
            prompt: nil,
            audioDurationSeconds: 12
        )

        #expect(text == "retried successfully")
        #expect(attempts.value() == 2)
    }

    @Test func openAIRewriteServiceUsesFallbackOutputParsing() async throws {
        let session = TestURLSessionFactory.makeSession { request in
            let body = try JSONSerialization.jsonObject(with: TestSupport.requestBodyData(from: request)) as? [String: Any]
            let input = try #require(body?["input"] as? [[String: Any]])
            #expect((input.first?["role"] as? String) == "system")
            #expect((input.last?["content"] as? String)?.contains("Instruction:") == true)

            let response = HTTPURLResponse(url: try #require(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!
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
                          "text": "rewritten",
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
            configuration: OpenAIConfiguration(apiKey: "sk-test", baseURL: URL(string: "https://api.example.com/v1")!),
            session: session
        )

        let text = try await service.rewrite(
            .rewriteSelection(
                sourceText: "hello",
                instruction: "Make it concise",
                preferredSpellings: ["OpenAI"]
            )
        )

        #expect(text == "rewritten")
    }

    @Test func openAIRewriteServiceMapsProviderErrors() async {
        let session = TestURLSessionFactory.makeSession { request in
            let response = HTTPURLResponse(url: try #require(request.url), statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"error":{"message":"bad key","type":"invalid_request_error","param":null,"code":null}}"#.utf8))
        }
        let service = OpenAIRewriteService(
            configuration: OpenAIConfiguration(apiKey: "sk-test", baseURL: URL(string: "https://api.example.com/v1")!),
            session: session
        )

        await #expect(throws: OpenAIError.api(provider: .openAI, statusCode: 401, message: "bad key")) {
            try await service.rewrite(.rewriteSelection(sourceText: "hello", instruction: "Make it concise"))
        }
    }
}
