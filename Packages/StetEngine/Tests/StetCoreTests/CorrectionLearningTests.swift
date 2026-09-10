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
                    root.appendingPathComponent("scripts/correction_learning/glossary_cases.json")))
        for item in cases {
            #expect(
                GlossaryEntry.merging(item.existing.map(\.entry), terms: item.terms, source: item.source)
                    == item.expected,
                "Python glossary fixture: \(item.id)")
        }
    }

    @Test func pythonContextCombinations() throws {
        let corrections = [
            ("Pyton", "Python"), ("拍图", "Python"), ("明天", "后天"), ("苹果", "芒果"),
            ("C plus plus", "C++"), ("get_usr_id", "get_user_id"), ("post grass", "PostgreSQL"),
            ("cafe", "café"), ("new york", "New York"), ("coffee", "tea"), ("X", "R"), ("3", "4"),
        ]
        for (before, after) in corrections {
            for prefix in ["", "前文：", "Use ", "😀 ", "first\n", "(", "  ", "\t"] {
                for suffix in ["", "。", " today", " 后文", " 😄", "\nend", ")", "\t"] {
                    #expect(
                        try CorrectionExtractor.extract(
                            original: prefix + before + suffix, edited: prefix + after + suffix)
                            == [.init(original: before, replacement: after)])
                }
            }
        }
    }

    @Test func pythonRepeatedInsertionAndDeletionCombinations() throws {
        for count in 1...40 {
            let words = Array(repeating: "repeat", count: count)
            for position in 0...count {
                let original = words.joined(separator: " ")
                let edited = (Array(words[..<position]) + ["added"] + Array(words[position...])).joined(separator: " ")
                #expect(try CorrectionExtractor.extract(original: original, edited: edited).isEmpty)
                #expect(try CorrectionExtractor.extract(original: edited, edited: original).isEmpty)
            }
        }
    }

    @Test func resourceLimitsMatchPython() {
        #expect(throws: CorrectionExtractor.ExtractionError.self) {
            try CorrectionExtractor.extract(original: String(repeating: "a", count: 32001), edited: "Python")
        }
        #expect(throws: CorrectionExtractor.ExtractionError.self) {
            try CorrectionExtractor.extract(original: String(repeating: "word ", count: 4097), edited: "Python")
        }
    }
    private struct Case: Decodable {
        let id: String
        let original: String
        let edited: String
        let expected: [TextCorrection]
    }

    @Test func pythonFixtures() throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let cases = try JSONDecoder().decode(
            [Case].self,
            from: Data(contentsOf: root.appendingPathComponent("scripts/correction_learning/cases.json"))
        )
        for item in cases {
            #expect(
                try CorrectionExtractor.extract(original: item.original, edited: item.edited) == item.expected,
                "Python fixture: \(item.id)")
        }
    }

    @Test func manualProvenanceSurvivesAutomaticLearning() {
        #expect(
            GlossaryEntry.merging(
                [.init(term: "Python", source: .manual)], terms: ["python", "Swift"], source: .automatic
            ) == [.init(term: "Python", source: .manual), .init(term: "Swift", source: .automatic)])
    }
}
