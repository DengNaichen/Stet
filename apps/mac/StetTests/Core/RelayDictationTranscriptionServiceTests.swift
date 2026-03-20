import Foundation
import Testing

@testable import Stet

@Suite("Relay Dictation Transcription Service", .serialized)
struct RelayDictationTranscriptionServiceTests {
    private let authentication = RelayAuthenticationContext(
        functionsBaseURL: URL(string: "https://example.supabase.co/functions/v1")!,
        publishableKey: "anon-key",
        accessToken: "access-token"
    )

    @Test func transcribeBuildsManagedRelayMultipartRequest() async throws {
        let fileURL = TestSupport.temporaryFileURL("relay-upload", ext: "wav")
        try Data("wav-data".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        var capturedRequest: URLRequest?
        let session = TestURLSessionFactory.makeSession { request in
            capturedRequest = request
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["x-request-id": "req_success"]
                )!,
                Data(#"{"text":"Relay transcript","rewritten":true}"#.utf8)
            )
        }

        let service = RelayDictationTranscriptionService(
            authentication: authentication,
            session: session,
            rewriteEnabled: true,
            preferredSpellings: ["OpenAI", "Groq"]
        )

        let result = try await service.transcribe(
            audioFileAt: fileURL,
            languageCode: "en",
            prompt: "Use OpenAI and Groq exactly.",
            audioDurationSeconds: 4
        )

        let request = try #require(capturedRequest)
        let requestBody = try TestSupport.requestBodyData(from: request)
        let requestBodyText = try #require(String(data: requestBody, encoding: .utf8))

        #expect(result == "Relay transcript")
        #expect(request.url?.absoluteString == "https://example.supabase.co/functions/v1/relay/v1/audio/transcriptions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer access-token")
        #expect(request.value(forHTTPHeaderField: "Apikey") == "anon-key")
        #expect(request.value(forHTTPHeaderField: "Content-Type")?.contains("multipart/form-data; boundary=") == true)
        #expect(requestBodyText.contains("name=\"rewrite\""))
        #expect(requestBodyText.contains("\r\ntrue\r\n"))
        #expect(requestBodyText.contains("name=\"preferred_spellings\""))
        #expect(requestBodyText.contains("OpenAI, Groq"))
        #expect(requestBodyText.contains("name=\"language\""))
        #expect(requestBodyText.contains("\r\nen\r\n"))
        #expect(requestBodyText.contains("name=\"prompt\""))
        #expect(requestBodyText.contains("Use OpenAI and Groq exactly."))
        #expect(requestBodyText.contains("name=\"audio_duration_seconds\""))
        #expect(requestBodyText.contains("4.000"))
        #expect(requestBodyText.contains("name=\"file\"; filename=\"speech.wav\""))
    }

    @Test func transcribeMapsRelayErrors() async {
        let fileURL = TestSupport.temporaryFileURL("relay-upload-error", ext: "wav")
        try? Data("wav-data".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let session = TestURLSessionFactory.makeSession { request in
            (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 429,
                    httpVersion: nil,
                    headerFields: ["x-request-id": "req_error"]
                )!,
                Data(#"{"code":"quota_error","message":"quota exceeded","request_id":"req_payload"}"#.utf8)
            )
        }

        let service = RelayDictationTranscriptionService(
            authentication: authentication,
            session: session,
            rewriteEnabled: false,
            preferredSpellings: []
        )

        await #expect(throws: AIExecutionError.relayInvocationFailed(
            statusCode: 429,
            message: "[quota_error] quota exceeded",
            requestID: "req_payload"
        )) {
            try await service.transcribe(
                audioFileAt: fileURL,
                languageCode: nil,
                prompt: nil,
                audioDurationSeconds: 4
            )
        }
    }

    @Test func transcribeRejectsSuccessfulPayloadWithoutText() async {
        let fileURL = TestSupport.temporaryFileURL("relay-upload-empty", ext: "wav")
        try? Data("wav-data".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let session = TestURLSessionFactory.makeSession { request in
            (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["x-request-id": "req_empty"]
                )!,
                Data(#"{"text":"   ","rewritten":false}"#.utf8)
            )
        }

        let service = RelayDictationTranscriptionService(
            authentication: authentication,
            session: session,
            rewriteEnabled: false,
            preferredSpellings: []
        )

        await #expect(throws: AIExecutionError.relayInvocationFailed(
            statusCode: 200,
            message: "The relay response did not contain any text.",
            requestID: "req_empty"
        )) {
            try await service.transcribe(
                audioFileAt: fileURL,
                languageCode: nil,
                prompt: nil,
                audioDurationSeconds: 4
            )
        }
    }
}
