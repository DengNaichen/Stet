import Foundation

public enum HotwordLearningState: String, Codable, Sendable {
    case notEligible
    case pending
    case inFlight
    case completed
    case retryable
    case permanentFailure
}

public struct HotwordLearningTerm: Codable, Equatable, Sendable {
    public let term: String
    public let source: GlossaryEntry.Source

    public init(term: String, source: GlossaryEntry.Source) {
        self.term = term
        self.source = source
    }
}

public struct HotwordLearningHistory: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let hotwords: [HotwordLearningTerm]
    public let withHotwords: String
    public let withoutHotwords: String

    public init(
        id: UUID,
        hotwords: [HotwordLearningTerm],
        withHotwords: String,
        withoutHotwords: String
    ) {
        self.id = id
        self.hotwords = hotwords
        self.withHotwords = withHotwords
        self.withoutHotwords = withoutHotwords
    }
}

public struct HotwordLearningBatchRequest: Codable, Equatable, Sendable {
    public let version: Int
    public let histories: [HotwordLearningHistory]

    public init(version: Int = 1, histories: [HotwordLearningHistory]) {
        self.version = version
        self.histories = histories
    }
}

public struct HotwordLearningBatchResponse: Codable, Equatable, Sendable {
    public let version: Int
    public let unnecessaryHotwords: [String]

    public init(version: Int, unnecessaryHotwords: [String]) {
        self.version = version
        self.unnecessaryHotwords = unnecessaryHotwords
    }
}

public enum HotwordLearningValidationError: Error, Equatable, Sendable {
    case unsupportedVersion
    case invalidBatchSize
    case duplicateHistoryID
    case duplicateTerm
    case unknownTerm
}

public enum HotwordLearningBatchValidator {
    public static let maximumBatchSize = 20

    public static func validate(
        _ response: HotwordLearningBatchResponse,
        for request: HotwordLearningBatchRequest
    ) throws -> [String] {
        guard request.version == 1, response.version == request.version else {
            throw HotwordLearningValidationError.unsupportedVersion
        }
        guard !request.histories.isEmpty, request.histories.count <= maximumBatchSize else {
            throw HotwordLearningValidationError.invalidBatchSize
        }
        guard Set(request.histories.map(\.id)).count == request.histories.count else {
            throw HotwordLearningValidationError.duplicateHistoryID
        }
        let allowed = Set(request.histories.flatMap(\.hotwords).map { Self.key($0.term) })
        var seen = Set<String>()
        for term in response.unnecessaryHotwords {
            let key = Self.key(term)
            guard seen.insert(key).inserted else {
                throw HotwordLearningValidationError.duplicateTerm
            }
            guard allowed.contains(key) else {
                throw HotwordLearningValidationError.unknownTerm
            }
        }
        return response.unnecessaryHotwords
    }

    private static func key(_ term: String) -> String {
        term.precomposedStringWithCanonicalMapping
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .lowercased()
    }
}
