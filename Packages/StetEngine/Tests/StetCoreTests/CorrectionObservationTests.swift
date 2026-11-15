import Foundation
import Testing
@testable import StetCore

struct CorrectionObservationTests {
    @Test func holdsIntermediateEditsAndSettlesOnlyOnceAtSessionEnd() throws {
        var observation = try #require(
            CorrectionObservation(
                before: "prefix  suffix",
                selection: NSRange(location: 7, length: 0),
                inserted: "拍图",
                startedAt: 0
            )
        )
        #expect(observation.sample("prefix Python suffix", at: 0.1) == .waiting)
        #expect(observation.sample("prefix 拍图 suffix", at: 0.2) == .waiting)
        // Intermediate IME / typing states never trigger early learning, even past 1s.
        #expect(observation.sample("prefix pai suffix", at: 0.4) == .waiting)
        #expect(observation.sample("prefix pai suffix", at: 2.0) == .waiting)
        #expect(observation.sample("prefix Python suffix", at: 2.5) == .waiting)
        #expect(observation.sample("prefix Python suffix", at: 5.0) == .waiting)

        #expect(
            observation.finish(triggeredByCompletionKey: false, at: 5.5)
                == .evaluate(.init(original: "拍图", edited: "Python"))
        )
        #expect(observation.finish(triggeredByCompletionKey: false, at: 6.0) == .finished)
    }

    @Test func completionKeySettlesLastNonEmptySnapshotEvenAfterChatClearsField() throws {
        var observation = try #require(
            CorrectionObservation(
                before: "",
                selection: NSRange(location: 0, length: 0),
                inserted: "我最近在学拍图",
                startedAt: 0
            )
        )
        #expect(observation.sample("我最近在学拍图", at: 0.1) == .waiting)
        #expect(observation.sample("我最近在学 Python", at: 0.8) == .waiting)
        // Simulate a poll landing milliseconds after Return cleared the chat input box.
        #expect(observation.sample("", at: 1.0) == .waiting)

        #expect(
            observation.finish(currentField: "", triggeredByCompletionKey: true, at: 1.05)
                == .evaluate(.init(original: "我最近在学拍图", edited: "我最近在学 Python"))
        )
    }

    @Test func clearingFieldWithoutCompletionKeyDoesNotEvaluate() throws {
        var observation = try #require(
            CorrectionObservation(
                before: "",
                selection: NSRange(location: 0, length: 0),
                inserted: "我最近在学拍图",
                startedAt: 0
            )
        )
        #expect(observation.sample("我最近在学拍图", at: 0.1) == .waiting)
        #expect(observation.sample("我最近在学 Python", at: 0.5) == .waiting)
        #expect(observation.sample("", at: 1.0) == .waiting)
        #expect(observation.finish(currentField: "", triggeredByCompletionKey: false, at: 1.2) == .finished)
    }

    @Test func outsideEditsAndUnverifiedPasteDoNotLeakSurroundingText() throws {
        var uneditedOutside = try #require(
            CorrectionObservation(
                before: "hello old",
                selection: NSRange(location: 6, length: 3),
                inserted: "Pyton",
                startedAt: 0
            )
        )
        #expect(uneditedOutside.sample("hello Pyton", at: 0.1) == .waiting)
        #expect(uneditedOutside.sample("bye Python", at: 0.3) == .finished)
        #expect(uneditedOutside.sample("hello Python", at: 3.0) == .finished)

        var editedThenOutside = try #require(
            CorrectionObservation(
                before: "hello ",
                selection: NSRange(location: 6, length: 0),
                inserted: "Pyton",
                startedAt: 0
            )
        )
        #expect(editedThenOutside.sample("hello Pyton", at: 0.1) == .waiting)
        #expect(editedThenOutside.sample("hello Python", at: 0.4) == .waiting)
        #expect(
            editedThenOutside.sample("hi Python", at: 0.8)
                == .evaluate(.init(original: "Pyton", edited: "Python"))
        )

        var blind = try #require(
            CorrectionObservation(
                before: "",
                selection: NSRange(location: 0, length: 0),
                inserted: "Pyton",
                startedAt: 0
            )
        )
        #expect(blind.sample("Python", at: 2.5) == .finished)
    }

    @Test func handlesUTF16EmojiSelectionAndDeadlineSettlement() throws {
        var observation = try #require(
            CorrectionObservation(
                before: "😀旧词!",
                selection: NSRange(location: 2, length: 2),
                inserted: "拍图",
                startedAt: 0
            )
        )
        #expect(observation.sample("😀拍图!", at: 0.1) == .waiting)
        #expect(observation.sample("😀Python!", at: 0.4) == .waiting)
        #expect(
            observation.sample("😀IgnoredAfterDeadline!", at: 30.5)
                == .evaluate(.init(original: "拍图", edited: "Python"))
        )
        #expect(
            CorrectionObservation(before: "😀", selection: .init(location: 1, length: 1), inserted: "x", startedAt: 0)
                == nil
        )
    }

    @Test func localPreFilterSkipsTrivialEditsAndKeepsWordRepairs() {
        #expect(!CorrectionObservation.shouldEvaluate(original: "Hello, world!", edited: "Hello， world。"))
        #expect(!CorrectionObservation.shouldEvaluate(original: "今天开心😀", edited: "今天开心😄"))
        #expect(!CorrectionObservation.shouldEvaluate(original: "I use Python", edited: "I use Python daily"))
        #expect(!CorrectionObservation.shouldEvaluate(original: "我用Python", edited: "我用Python写代码"))
        #expect(!CorrectionObservation.shouldEvaluate(original: "今天天气不错", edited: "今天天气不错出去走走"))
        #expect(!CorrectionObservation.shouldEvaluate(original: "I often use Python", edited: "I use Python"))
        #expect(!CorrectionObservation.shouldEvaluate(original: "我经常用Python", edited: "我用Python"))

        #expect(CorrectionObservation.shouldEvaluate(original: "我最近在学拍图", edited: "我最近在学 Python"))
        #expect(CorrectionObservation.shouldEvaluate(original: "use python", edited: "use Python"))
        #expect(CorrectionObservation.shouldEvaluate(original: "Pytho", edited: "Python"))
        #expect(CorrectionObservation.shouldEvaluate(original: "I use Pythhon", edited: "I use Python"))
        #expect(CorrectionObservation.shouldEvaluate(original: "看一下这个接口", edited: "看一下这个 GraphQL 接口"))
    }
}
