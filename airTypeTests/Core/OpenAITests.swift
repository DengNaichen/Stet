import Foundation
import Testing

@testable import airType

@MainActor
@Suite("OpenAI Adapters", .serialized)
struct OpenAITests {
    @Test func openAIClientBuildsJSONRequestHeadersAndRelativeURL() async throws {
        let session = TestURLSessionFactory.makeSession()
        let configuration = OpenAIConfiguration(
            apiKey: "sk-test",
            baseURL: URL(string: "https://api.example.com/v1")!,
            organizationID: "org_123",
            projectID: "proj_123"
        )
        let client = OpenAIClient(configuration: configuration, session: session)

        URLProtocolStub.configure { request in
            let body = try TestSupport.requestBodyData(from: request)
            #expect(request.url?.absoluteString == "https://api.example.com/v1/responses")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
            #expect(request.value(forHTTPHeaderField: "OpenAI-Organization") == "org_123")
            #expect(request.value(forHTTPHeaderField: "OpenAI-Project") == "proj_123")
            #expect(String(data: body, encoding: .utf8)?.contains("\"ping\":true") == true)

            let response = HTTPURLResponse(url: try #require(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"ok":true}"#.utf8))
        }
        defer { URLProtocolStub.reset() }

        let response: TestResponse = try await client.sendJSONRequest(path: "/responses", body: ["ping": true])

        #expect(response.ok)
    }

    @Test func openAIClientParsesAPIEnvelopeErrors() async {
        let session = TestURLSessionFactory.makeSession()
        let client = OpenAIClient(configuration: OpenAIConfiguration(apiKey: "sk-test"), session: session)

        URLProtocolStub.configure { request in
            let response = HTTPURLResponse(url: try #require(request.url), statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"error":{"message":"bad key"}}"#.utf8))
        }
        defer { URLProtocolStub.reset() }

        await #expect(throws: OpenAIError.api(statusCode: 401, message: "bad key")) {
            let _: TestResponse = try await client.sendJSONRequest(path: "/responses", body: ["ping": true])
        }
    }

    @Test func openAITranscriptionServiceSendsMultipartFields() async throws {
        let fileURL = TestSupport.temporaryFileURL(ext: "m4a")
        try Data("audio-bytes".utf8).write(to: fileURL)
        let session = TestURLSessionFactory.makeSession()
        let service = OpenAITranscriptionService(
            configuration: OpenAIConfiguration(apiKey: "sk-test", baseURL: URL(string: "https://api.example.com/v1")!),
            session: session
        )

        URLProtocolStub.configure { request in
            let body = String(data: try TestSupport.requestBodyData(from: request), encoding: .utf8) ?? ""
            #expect(body.contains("name=\"model\""))
            #expect(body.contains("gpt-4o-mini-transcribe"))
            #expect(request.value(forHTTPHeaderField: "X-AirType-Audio-Duration-Seconds") == "3")
            #expect(body.contains("name=\"language\""))
            #expect(body.contains("de"))
            #expect(body.contains("name=\"prompt\""))
            #expect(body.contains("Use OpenAI"))
            #expect(body.contains("filename=\"\(fileURL.lastPathComponent)\""))

            let response = HTTPURLResponse(url: try #require(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"text":"hello"}"#.utf8))
        }
        defer {
            URLProtocolStub.reset()
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

    @Test func openAITranscriptionServiceThrowsWhenTextIsMissing() async throws {
        let fileURL = TestSupport.temporaryFileURL(ext: "wav")
        try Data("audio-bytes".utf8).write(to: fileURL)
        let session = TestURLSessionFactory.makeSession()
        let service = OpenAITranscriptionService(
            configuration: OpenAIConfiguration(apiKey: "sk-test", baseURL: URL(string: "https://api.example.com/v1")!),
            session: session
        )

        URLProtocolStub.configure { request in
            let response = HTTPURLResponse(url: try #require(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"text":"   "}"#.utf8))
        }
        defer {
            URLProtocolStub.reset()
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

    @Test func openAIRewriteServiceUsesFallbackOutputParsing() async throws {
        let session = TestURLSessionFactory.makeSession()
        let service = OpenAIRewriteService(
            configuration: OpenAIConfiguration(apiKey: "sk-test", baseURL: URL(string: "https://api.example.com/v1")!),
            session: session
        )

        URLProtocolStub.configure { request in
            let body = try JSONSerialization.jsonObject(with: TestSupport.requestBodyData(from: request)) as? [String: Any]
            let input = try #require(body?["input"] as? [[String: Any]])
            #expect((input.first?["role"] as? String) == "system")
            #expect((input.last?["content"] as? String)?.contains("Instruction:") == true)

            let response = HTTPURLResponse(url: try #require(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = Data(#"{"output":[{"type":"message","content":[{"type":"output_text","text":"rewritten"}]}]}"#.utf8)
            return (response, data)
        }
        defer { URLProtocolStub.reset() }

        let text = try await service.rewrite(
            .rewriteSelection(
                sourceText: "hello",
                instruction: "Make it concise",
                preferredSpellings: ["OpenAI"],
                contextInstructions: "Use docs tone"
            )
        )

        #expect(text == "rewritten")
    }

    @Test func openAITranslationServiceBuildsTargetLanguagePromptAndThrowsOnMissingText() async {
        let session = TestURLSessionFactory.makeSession()
        let service = OpenAITranslationService(
            configuration: OpenAIConfiguration(apiKey: "sk-test", baseURL: URL(string: "https://api.example.com/v1")!),
            session: session
        )

        URLProtocolStub.configure { request in
            let body = try JSONSerialization.jsonObject(with: TestSupport.requestBodyData(from: request)) as? [String: Any]
            let input = try #require(body?["input"] as? [[String: Any]])
            let userContent = input.last?["content"] as? String
            #expect(userContent?.contains("Target language:") == true)
            #expect(userContent?.contains("Japanese") == true)

            let response = HTTPURLResponse(url: try #require(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"output":[]}"#.utf8))
        }
        defer { URLProtocolStub.reset() }

        await #expect(throws: OpenAIError.missingTranslationText) {
            try await service.translate(.translate("hello", to: .japanese))
        }
    }
}

private struct TestResponse: Decodable {
    let ok: Bool
}
