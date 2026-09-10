import Foundation
import Testing
@testable import StetCore

struct CorrectionObservationTests {
    @Test func learnsOnlyTheInsertedRegionAfterPasteAndStableEdit() throws {
        var observation = try #require(
            CorrectionObservation(
                before: "prefix  suffix", selection: NSRange(location: 7, length: 0), inserted: "拍图", startedAt: 0
            ))
        #expect(observation.sample("prefix Python suffix", at: 0.1) == .waiting)
        #expect(observation.sample("prefix 拍图 suffix", at: 0.2) == .waiting)
        #expect(observation.sample("prefix Python suffix", at: 0.4) == .waiting)
        #expect(
            observation.sample("prefix Python suffix", at: 1.5)
                == .learn([
                    .init(original: "拍图", replacement: "Python")
                ]))
        #expect(observation.sample("prefix Python suffix", at: 2) == .waiting)
    }

    @Test func outsideEditsAndUnverifiedPasteDoNotLearn() throws {
        var observation = try #require(
            CorrectionObservation(
                before: "hello old", selection: NSRange(location: 6, length: 3), inserted: "Pyton", startedAt: 0
            ))
        #expect(observation.sample("hello Pyton", at: 0.1) == .waiting)
        #expect(observation.sample("bye Python", at: 0.3) == .finished)
        #expect(observation.sample("hello Python", at: 3) == .finished)
        var blind = try #require(
            CorrectionObservation(before: "", selection: .init(location: 0, length: 0), inserted: "Pyton", startedAt: 0)
        )
        #expect(blind.sample("Python", at: 3) == .finished)
    }

    @Test func handlesUTF16SelectionAndFlushesOnCompletionWithoutClaimingSent() throws {
        var observation = try #require(
            CorrectionObservation(
                before: "😀旧词!", selection: NSRange(location: 2, length: 2), inserted: "拍图", startedAt: 0
            ))
        #expect(observation.sample("😀拍图!", at: 0.1) == .waiting)
        #expect(
            observation.sample("😀Python!", at: 0.2, finishing: true)
                == .learn([
                    .init(original: "拍图", replacement: "Python")
                ]))
        #expect(observation.sample("😀Rust!", at: 0.3) == .finished)
    }

    @Test func deletionUndoAndTimeoutDoNotCreateTerms() throws {
        var observation = try #require(
            CorrectionObservation(before: "", selection: .init(location: 0, length: 0), inserted: "Pyton", startedAt: 0)
        )
        #expect(observation.sample("Pyton", at: 0.1) == .waiting)
        #expect(observation.sample("Python", at: 0.2) == .waiting)
        #expect(observation.sample("Pyton", at: 0.3) == .waiting)
        #expect(observation.sample("Pyton", at: 1.5) == .waiting)
        #expect(observation.sample("", at: 1.6) == .waiting)
        #expect(observation.sample("", at: 3) == .waiting)
        #expect(observation.sample("Python", at: 31) == .finished)
        #expect(
            CorrectionObservation(before: "😀", selection: .init(location: 1, length: 1), inserted: "x", startedAt: 0)
                == nil)
    }
}
