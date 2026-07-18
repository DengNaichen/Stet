import Foundation

public struct StructuredRewriteOutput: Codable, Sendable, Equatable {
    public let text: String

    public init(text: String) {
        self.text = text
    }

    public nonisolated static let schemaName = "rewrite_output"
    public nonisolated static let schemaDescription =
        "The final cleaned transcript in a machine-readable response."
    public nonisolated static let jsonSchema = StructuredRewriteJSONSchema()
}

public struct StructuredRewriteJSONSchema: Encodable, Sendable, Equatable {
    public struct Properties: Encodable, Sendable, Equatable {
        public struct TextProperty: Encodable, Sendable, Equatable {
            public let type = "string"
            public let description = "The final cleaned transcript, ready to paste."

            public init() {}
        }

        public let text = TextProperty()

        public init() {}
    }

    public let type = "object"
    public let properties = Properties()
    public let required = ["text"]
    public let additionalProperties = false

    public init() {}
}

public enum StructuredRewriteOutputError: Error, Sendable, Equatable {
    case invalidJSON
    case emptyText
}

public enum StructuredRewriteOutputDecoder {
    public nonisolated static func decodeText(from content: String) throws -> String {
        let output: StructuredRewriteOutput
        do {
            output = try JSONDecoder().decode(
                StructuredRewriteOutput.self,
                from: Data(content.utf8)
            )
        } catch {
            throw StructuredRewriteOutputError.invalidJSON
        }

        let text = output.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw StructuredRewriteOutputError.emptyText
        }
        return text
    }
}
