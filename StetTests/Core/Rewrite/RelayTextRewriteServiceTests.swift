import Foundation
import Testing

@testable import Stet

@Suite("Relay Text Rewrite Service", .serialized)
struct RelayTextRewriteServiceTests {
    private let authentication = RelayAuthenticationContext(
        functionsBaseURL: URL(string: "https://example.supabase.co/functions/v1")!,
        publishableKey: "anon-key",
        accessToken: "access-token"
    )

    @Test func rewriteBuildsManagedRelayJSONRequest() async throws {
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
                Data(#"{"text":"Rewritten relay transcript"}"#.utf8)
            )
        }

        let service = RelayTextRewriteService(
            authentication: authentication,
            session: session
        )

        let result = try await service.rewrite(
            .cleanup(
                "raw transcript",
                audience: .ai,
                preferredSpellings: ["Stet", "Whisper"],
                additionalContext: "mix Chinese and English"
            )
        )

        let request = try #require(capturedRequest)
        let requestBody = try TestSupport.requestBodyData(from: request)
        let payload = try #require(
            JSONSerialization.jsonObject(with: requestBody) as? [String: Any]
        )

        #expect(result == "Rewritten relay transcript")
        #expect(request.url?.absoluteString == "https://example.supabase.co/functions/v1/relay/v1/text/rewrites")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer access-token")
        #expect(request.value(forHTTPHeaderField: "Apikey") == "anon-key")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(payload["text"] as? String == "raw transcript")
        #expect(payload["audience"] as? String == "ai")
        #expect(payload["additionalContext"] as? String == "mix Chinese and English")
        #expect((payload["preferredSpellings"] as? [String]) == ["Stet", "Whisper"])
    }

    @Test func rewriteUsesFreshAuthenticationWhenProviderReturnsUpdatedSession() async throws {
        var capturedRequest: URLRequest?
        let refreshedAuthentication = RelayAuthenticationContext(
            functionsBaseURL: URL(string: "https://example.supabase.co/functions/v1")!,
            publishableKey: "anon-key",
            accessToken: "refreshed-access-token"
        )
        let session = TestURLSessionFactory.makeSession { request in
            capturedRequest = request
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: [:]
                )!,
                Data(#"{"text":"Rewritten relay transcript"}"#.utf8)
            )
        }

        let service = RelayTextRewriteService(
            authentication: authentication,
            authenticationProvider: { refreshedAuthentication },
            session: session
        )

        _ = try await service.rewrite(.cleanup("raw transcript"))

        let request = try #require(capturedRequest)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer refreshed-access-token")
    }

    @Test func rewriteMapsRelayErrors() async {
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

        let service = RelayTextRewriteService(
            authentication: authentication,
            session: session
        )

        await #expect(
            throws: AIExecutionError.relayInvocationFailed(
                statusCode: 429,
                message: "[quota_error] quota exceeded",
                requestID: "req_payload"
            )
        ) {
            try await service.rewrite(.cleanup("raw transcript"))
        }
    }

    @Test func rewriteRejectsSuccessfulPayloadWithoutText() async {
        let session = TestURLSessionFactory.makeSession { request in
            (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["x-request-id": "req_empty"]
                )!,
                Data(#"{"text":"   "}"#.utf8)
            )
        }

        let service = RelayTextRewriteService(
            authentication: authentication,
            session: session
        )

        await #expect(
            throws: AIExecutionError.relayInvocationFailed(
                statusCode: 200,
                message: "The relay response did not contain any text.",
                requestID: "req_empty"
            )
        ) {
            try await service.rewrite(.cleanup("raw transcript"))
        }
    }
}
