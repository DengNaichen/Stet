import Foundation
import StetCore
import StetRewrite
import Testing

struct GlossaryLearningDecisionTests {
    @Test func decodesLearnDecisionAndKeepsExactEditedSubstrings() throws {
        let pair = CorrectionEditPair(
            original: "我最近在学拍图，把配置写进 herder 里",
            edited: "我最近在学 Python，把配置写进 Herdr 里"
        )
        let json = """
            ```json
            {"decision":"learn","reason":"ASR phonetic and spelling fixes","terms":["Python","Herdr"]}
            ```
            """
        let terms = try GlossaryLearningOutputDecoder.decodeValidatedTerms(from: json, pair: pair)
        #expect(terms == ["Python", "Herdr"])
    }

    @Test func ignoreDecisionAlwaysProducesEmptyListEvenIfModelReturnedTerms() throws {
        let pair = CorrectionEditPair(original: "明天开会", edited: "后天开会")
        let json = #"{"decision":"ignore","reason":"Changed date","terms":["后天"]}"#
        let terms = try GlossaryLearningOutputDecoder.decodeValidatedTerms(from: json, pair: pair)
        #expect(terms.isEmpty)
    }

    @Test func physicalGuardrailsDropHallucinatedUnchangedChoppedAndOversizedTerms() throws {
        let pair = CorrectionEditPair(
            original: "我刚装了 Python，用了 Pythons 和拍图，感觉不错",
            edited: "我刚装了 Python，用了 Python 和 GraphQL，顺便今天下午我们一起把整套架构全部重构一遍吧"
        )
        let json = #"""
            {
              "decision": "learn",
              "reason": "Mixed candidates",
              "terms": [
                "GraphQL",
                "graphql",
                "Python",
                "Graph",
                "NotInEdited",
                "顺便今天下午我们一起把整套架构",
                "too many english words here now",
                "bad,comma"
              ]
            }
            """#
        let terms = try GlossaryLearningOutputDecoder.decodeValidatedTerms(from: json, pair: pair)
        // "GraphQL" is newly inserted; "Python" increased from 1 standalone occurrence ("Pythons" != "Python") to 2;
        // "graphql" (wrong casing), "Graph" (chopped prefix), "NotInEdited", clauses, and comma terms are dropped.
        #expect(terms == ["GraphQL", "Python"])
    }

    @Test func rejectsUnchangedTermWhenCountDidNotIncrease() throws {
        let pair = CorrectionEditPair(
            original: "我刚装了 Python，感觉不错",
            edited: "我刚装了 Python，非常好用"
        )
        let json = #"{"decision":"learn","reason":"Mistakenly extracted unchanged term","terms":["Python"]}"#
        let terms = try GlossaryLearningOutputDecoder.decodeValidatedTerms(from: json, pair: pair)
        #expect(terms.isEmpty)
    }
}
