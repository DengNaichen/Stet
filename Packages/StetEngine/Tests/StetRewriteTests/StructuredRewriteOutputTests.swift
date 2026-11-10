import Foundation
import StetCore
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

    @Test func preparedCloudRewritePayloadPlacesAppNameAtEndAndPartitionsAffinityKey() throws {
        let humanPayload = PreparedCloudRewritePayload(
            request: .cleanup(
                "raw transcript",
                audience: .human,
                preferredSpellings: ["Stet"],
                languageCode: "zh",
                appName: "Slack"
            )
        )
        let aiPayload = PreparedCloudRewritePayload(
            request: .cleanup(
                "raw transcript",
                audience: .ai,
                preferredSpellings: ["Stet"],
                languageCode: "zh",
                appName: "Cursor"
            )
        )

        #expect(humanPayload.cacheAffinityKey == "stet-rewrite-human")
        #expect(aiPayload.cacheAffinityKey == "stet-rewrite-ai")

        let dictionaryRange = try #require(
            aiPayload.systemPrompt.range(of: "Personal dictionary entries are canonical recovery targets: Stet.")
        )
        let structuredRange = try #require(
            aiPayload.systemPrompt.range(of: "Structured output: return exactly one JSON object")
        )
        let languageRange = try #require(
            aiPayload.systemPrompt.range(of: "Language lock: preserve the detected transcript language (zh) exactly.")
        )
        let appRange = try #require(
            aiPayload.systemPrompt.range(of: "The user is currently using the application: \"Cursor\".")
        )

        #expect(dictionaryRange.lowerBound < structuredRange.lowerBound)
        #expect(structuredRange.lowerBound < languageRange.lowerBound)
        #expect(languageRange.lowerBound < appRange.lowerBound)
    }
}
