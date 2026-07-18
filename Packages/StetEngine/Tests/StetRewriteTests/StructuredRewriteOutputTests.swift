import Foundation
import Testing

@testable import StetRewrite

struct StructuredRewriteOutputTests {
    @Test func decoderExtractsAndTrimsText() throws {
        let text = try StructuredRewriteOutputDecoder.decodeText(
            from: #"{"text":"  cleaned transcript\n"}"#
        )

        #expect(text == "cleaned transcript")
    }

    @Test func decoderRejectsMalformedJSON() {
        #expect(throws: StructuredRewriteOutputError.invalidJSON) {
            try StructuredRewriteOutputDecoder.decodeText(from: "plain text")
        }
    }

    @Test func decoderRejectsEmptyText() {
        #expect(throws: StructuredRewriteOutputError.emptyText) {
            try StructuredRewriteOutputDecoder.decodeText(from: #"{"text":"  "}"#)
        }
    }

    @Test func schemaRequiresOnlyTextAndRejectsAdditionalProperties() throws {
        let data = try JSONEncoder().encode(StructuredRewriteOutput.jsonSchema)
        let schema = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        #expect(schema["type"] as? String == "object")
        #expect(schema["required"] as? [String] == ["text"])
        #expect(schema["additionalProperties"] as? Bool == false)
        let properties = try #require(schema["properties"] as? [String: Any])
        #expect(Set(properties.keys) == ["text"])
    }
}
