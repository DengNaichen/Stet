import Foundation
import SwiftData
import Testing

@testable import StetCore

@Suite("Hot-word learning")
struct HotwordLearningTests {
    @Test func validatorAcceptsMixedSnapshots() throws {
        let request = HotwordLearningBatchRequest(histories: [
            history(hotwords: ["Cursor", "Stet"]),
            history(hotwords: ["Cursor", "DeepSeek"]),
        ])
        let response = HotwordLearningBatchResponse(version: 1, unnecessaryHotwords: ["Cursor"])
        #expect(try HotwordLearningBatchValidator.validate(response, for: request) == ["Cursor"])
    }

    @Test func validatorRejectsUnknownAndDuplicateTerms() {
        let request = HotwordLearningBatchRequest(histories: [history(hotwords: ["Stet"])])
        #expect(throws: HotwordLearningValidationError.unknownTerm) {
            try HotwordLearningBatchValidator.validate(
                .init(version: 1, unnecessaryHotwords: ["Other"]), for: request)
        }
        #expect(throws: HotwordLearningValidationError.duplicateTerm) {
            try HotwordLearningBatchValidator.validate(
                .init(version: 1, unnecessaryHotwords: ["Stet", "stet"]), for: request)
        }
    }

    @Test func validatorEnforcesTwentyItemBoundary() throws {
        let twenty = HotwordLearningBatchRequest(histories: (0..<20).map { _ in history() })
        _ = try HotwordLearningBatchValidator.validate(
            .init(version: 1, unnecessaryHotwords: []), for: twenty)
        let twentyOne = HotwordLearningBatchRequest(histories: (0..<21).map { _ in history() })
        #expect(throws: HotwordLearningValidationError.invalidBatchSize) {
            try HotwordLearningBatchValidator.validate(
                .init(version: 1, unnecessaryHotwords: []), for: twentyOne)
        }
    }

    @MainActor
    @Test func historyBecomesEligibleWithoutFinalTextAndCompletesIdempotently() throws {
        let schema = Schema([HistoryEntry.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        let id = UUID()
        context.insert(
            HistoryEntry(
                id: id,
                rawText: "Stet",
                rawTextWithoutHotwords: "step",
                hotwordLearningTerms: [.init(term: "Stet", source: .automatic)]
            ))
        try context.save()
        let service = DictationHistoryService(container: container)
        #expect(try service.fetchHotwordLearningCandidates().map(\.id) == [id])
        try service.markHotwordLearningInFlight(ids: [id])
        try service.recoverInterruptedHotwordLearning()
        #expect(try service.fetchRecent().first?.hotwordLearningState == .retryable)
        try service.completeHotwordLearning(ids: [id], suggestedTerms: ["Stet"])
        try service.completeHotwordLearning(ids: [id], suggestedTerms: ["Stet"])
        let entry = try #require(service.fetchRecent().first)
        #expect(entry.hotwordLearningState == .completed)
        #expect(entry.hotwordLearningSuggestedTerms == ["Stet"])
        #expect(entry.finalText == nil)
        #expect(try service.fetchHotwordLearningCandidates().isEmpty)
    }

    private func history(hotwords: [String] = ["Stet"]) -> HotwordLearningHistory {
        .init(
            id: UUID(),
            hotwords: hotwords.map { .init(term: $0, source: .automatic) },
            withHotwords: "with",
            withoutHotwords: "without"
        )
    }
}
