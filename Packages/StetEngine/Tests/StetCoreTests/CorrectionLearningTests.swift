import Foundation
import Testing
@testable import StetCore

struct CorrectionLearningTests {
    private struct LegacyOrEntry: Decodable {
        let entry: GlossaryEntry
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let term = try? container.decode(String.self) {
                entry = .init(term: term, source: .manual)
            } else {
                entry = try container.decode(GlossaryEntry.self)
            }
        }
    }

    private struct GlossaryCase: Decodable {
        let id: String
        let existing: [LegacyOrEntry]
        let terms: [String]
        let source: GlossaryEntry.Source
        let expected: [GlossaryEntry]
    }

    @Test func pythonGlossaryFixtures() throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let cases = try JSONDecoder().decode(
            [GlossaryCase].self,
            from: Data(
                contentsOf:
                    root.appendingPathComponent("scripts/correction_learning/glossary_cases.json"))
        )
        for item in cases {
            #expect(
                GlossaryEntry.merging(item.existing.map(\.entry), terms: item.terms, source: item.source)
                    == item.expected,
                "Python glossary fixture: \(item.id)"
            )
        }
    }

    @Test func manualProvenanceSurvivesAutomaticLearning() {
        #expect(
            GlossaryEntry.merging(
                [.init(term: "Python", source: .manual)],
                terms: ["python", "Swift"],
                source: .automatic
            ) == [.init(term: "Python", source: .manual), .init(term: "Swift", source: .automatic)]
        )
    }
}
