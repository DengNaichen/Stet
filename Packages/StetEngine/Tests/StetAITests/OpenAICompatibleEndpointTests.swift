import Foundation
import StetAI
import StetCore
import Testing

@Suite("OpenAI Compatible Endpoint")
struct OpenAICompatibleEndpointTests {
    @Test func normalizeAddsHTTPSAndV1WhenHostOnly() throws {
        let url = try OpenAICompatibleBaseURL.normalize("127.0.0.1:11434")
        #expect(url.absoluteString == "https://127.0.0.1:11434/v1")
    }

    @Test func normalizePreservesHTTPLocalhostAndAddsV1() throws {
        let url = try OpenAICompatibleBaseURL.normalize("http://127.0.0.1:11434")
        #expect(url.absoluteString == "http://127.0.0.1:11434/v1")
    }

    @Test func normalizeKeepsExistingVersionedPath() throws {
        let url = try OpenAICompatibleBaseURL.normalize("https://openrouter.ai/api/v1")
        #expect(url.absoluteString == "https://openrouter.ai/api/v1")
    }

    @Test func normalizeRejectsEmptyAndUnsupportedSchemes() {
        #expect(throws: OpenAIError.invalidBaseURL(provider: .custom)) {
            try OpenAICompatibleBaseURL.normalize("   ")
        }
        #expect(throws: OpenAIError.invalidBaseURL(provider: .custom)) {
            try OpenAICompatibleBaseURL.normalize("ftp://example.com/v1")
        }
    }

    @Test func catalogParsesUniqueSortedModelIDs() {
        let data = Data(
            """
            {"object":"list","data":[{"id":"llama3.1"},{"id":"gpt-4o"},{"id":"llama3.1"},{"id":"  "}]}
            """.utf8
        )

        #expect(OpenAICompatibleModelCatalog.modelIDs(from: data) == ["gpt-4o", "llama3.1"])
    }

    @Test func catalogReturnsEmptyListForUnknownPayloads() {
        #expect(OpenAICompatibleModelCatalog.modelIDs(from: Data("not-json".utf8)).isEmpty)
        #expect(OpenAICompatibleModelCatalog.modelIDs(from: Data("{}".utf8)).isEmpty)
    }
}
