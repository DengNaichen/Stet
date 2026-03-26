import Foundation
import Testing

@testable import Stet

@MainActor
@Suite("Provider Credential Validation", .serialized)
struct ProviderCredentialValidationServiceTests {
    @Test func openAIValidationCallsModelsEndpoint() async throws {
        let session = TestURLSessionFactory.makeSession { request in
            let requestURL = try #require(request.url)
            let components = try #require(URLComponents(url: requestURL, resolvingAgainstBaseURL: false))
            #expect(request.httpMethod == "GET")
            #expect(components.scheme == "https")
            #expect(components.host == "api.openai.com")
            #expect(components.path == "/v1/models")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-openai")
            #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")

            let response = HTTPURLResponse(url: requestURL, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"object":"list","data":[]}"#.utf8))
        }
        let service = ProviderCredentialValidationService(session: session)

        try await service.validateCredential(apiKey: "sk-openai", provider: .openAI)
    }

    @Test func groqValidationCallsGroqModelsEndpoint() async throws {
        let session = TestURLSessionFactory.makeSession { request in
            let requestURL = try #require(request.url)
            let components = try #require(URLComponents(url: requestURL, resolvingAgainstBaseURL: false))
            #expect(request.httpMethod == "GET")
            #expect(components.scheme == "https")
            #expect(components.host == "api.groq.com")
            #expect(components.path == "/openai/v1/models")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer gsk-live")

            let response = HTTPURLResponse(url: requestURL, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"object":"list","data":[]}"#.utf8))
        }
        let service = ProviderCredentialValidationService(session: session)

        try await service.validateCredential(apiKey: "gsk-live", provider: .groq)
    }

    @Test func validationRejectsMissingKeyBeforeMakingRequest() async {
        let service = ProviderCredentialValidationService(session: TestURLSessionFactory.makeSession())

        await #expect(throws: OpenAIError.missingAPIKey(provider: .openAI)) {
            try await service.validateCredential(apiKey: "   ", provider: .openAI)
        }
    }

    @Test func validationMapsProviderStatusCode() async {
        let session = TestURLSessionFactory.makeSession { request in
            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 401,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(#"{"error":{"message":"bad key"}}"#.utf8))
        }
        let service = ProviderCredentialValidationService(session: session)

        await #expect(throws: OpenAIError.api(provider: .openAI, statusCode: 401, message: "bad key")) {
            try await service.validateCredential(apiKey: "sk-bad", provider: .openAI)
        }
    }
}
