import Foundation
import Testing
@testable import StetCore

struct FunASRNanoHotwordPromptTests {
    @Test func prefersManualTermsAndCapsCount() {
        let automatic = (1...40).map { GlossaryEntry(term: "a\($0)", source: .automatic) }
        let manual = (1...15).map { GlossaryEntry(term: "M\($0)", source: .manual) }
        let terms = FunASRNanoHotwordPrompt.selectedTerms(from: automatic + manual)
        #expect(terms.count == FunASRNanoHotwordPrompt.maximumTermCount)
        #expect(terms.prefix(15).elementsEqual(manual.map(\.term)))
        #expect(terms.contains("a1"))
        #expect(!terms.contains("a40"))
    }

    @Test func stopsBeforeJoinedPromptExceedsCharacterBudget() throws {
        let long = String(repeating: "A", count: 80)
        let records = (1...20).map { GlossaryEntry(term: "\(long)\($0)", source: .manual) }
        let terms = FunASRNanoHotwordPrompt.selectedTerms(from: records)
        let prompt = try #require(FunASRNanoHotwordPrompt.makePrompt(from: records))
        #expect(terms.count < 20)
        #expect(prompt.count <= FunASRNanoHotwordPrompt.maximumJoinedCharacterCount)
        #expect(FunASRNanoHotwordPrompt.makePrompt(from: []) == nil)
    }
}
