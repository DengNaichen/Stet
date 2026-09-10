import Foundation

public struct GlossaryEntry: Codable, Equatable, Sendable {
    public enum Source: String, Codable, Sendable {
        case manual
        case automatic
    }

    public let term: String
    public let source: Source

    public init(term: String, source: Source) {
        self.term = term
        self.source = source
    }

    public static func merging(
        _ existing: [GlossaryEntry], terms: [String], source: Source
    ) -> [GlossaryEntry] {
        normalized(existing + terms.map { .init(term: $0, source: source) })
    }

    public static func normalized(_ entries: [GlossaryEntry]) -> [GlossaryEntry] {
        var result: [GlossaryEntry] = []
        var indexes: [String: Int] = [:]
        for entry in entries {
            let term = entry.term.precomposedStringWithCanonicalMapping.split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
            guard !term.isEmpty else { continue }
            let key = term.lowercased()
            if let index = indexes[key] {
                if result[index].source == .automatic, entry.source == .manual {
                    result[index] = .init(term: term, source: .manual)
                }
            } else {
                indexes[key] = result.count
                result.append(.init(term: term, source: entry.source))
            }
        }
        return result
    }
}
