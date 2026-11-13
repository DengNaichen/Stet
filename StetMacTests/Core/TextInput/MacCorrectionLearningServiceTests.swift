import Foundation
import StetCore
import Testing
@testable import Stet

@MainActor
@Suite("Correction learning integration", .serialized)
struct MacCorrectionLearningServiceTests {
    private func model() -> DictionaryModel {
        DictionaryModel(
            defaults: TestSupport.makeUserDefaults(),
            entriesKey: "dictionary.entries.\(UUID().uuidString)",
            enabledKey: "dictionary.enabled.\(UUID().uuidString)"
        )
    }

    private func observation(_ inserted: String = "我最近在学拍图") throws -> CorrectionObservation {
        try #require(
            CorrectionObservation(
                before: "",
                selection: .init(location: 0, length: 0),
                inserted: inserted,
                startedAt: 0
            )
        )
    }

    @Test func settlesOnlyAtObservationEndAndRecordsAutomaticTerms() async throws {
        let dictionary = model()
        defer { dictionary.clear() }

        var observedPairs: [CorrectionEditPair] = []
        let service = MacCorrectionLearningService(dictionary: dictionary) { pair in
            observedPairs.append(pair)
            return ["Python"]
        }

        var field = "我最近在学拍图"
        service.prepare(observation: try observation(), read: { .value(field) })
        service.sample(at: 0.1)

        // Intermediate IME / typing states never evaluate mid-window.
        field = "我最近在学 pai"
        service.sample(at: 0.3)
        service.sample(at: 1.8)
        #expect(observedPairs.isEmpty)
        #expect(dictionary.loadEntries().isEmpty)

        field = "我最近在学 Python"
        service.sample(at: 2.0)

        // Chat send clears the field right as Return fires.
        field = ""
        service.finishCurrentObservation(at: 2.1, triggeredByCompletionKey: true)
        await service.waitForPendingEvaluations()

        #expect(observedPairs == [.init(original: "我最近在学拍图", edited: "我最近在学 Python")])
        #expect(dictionary.loadRecords() == [.init(term: "Python", source: .automatic)])
    }

    @Test func switchingTargetSettlesCompletedEditWhileClearingWithoutReturnSkips() async throws {
        let dictionary = model()
        defer { dictionary.clear() }

        var evaluated: [CorrectionEditPair] = []
        let service = MacCorrectionLearningService(dictionary: dictionary) { pair in
            evaluated.append(pair)
            return pair.edited.contains("Swift") ? ["Swift"] : ["Python"]
        }

        var reading: MacCorrectionLearningService.Reading = .value("我最近在学拍图")
        service.prepare(observation: try observation(), read: { reading })
        service.sample(at: 0.1)
        reading = .value("我最近在学 Python")
        service.sample(at: 0.4)
        // User deletes all text without pressing Return, then switches focus.
        reading = .value("")
        service.sample(at: 0.8)
        reading = .differentTarget
        service.sample(at: 1.0)
        await service.waitForPendingEvaluations()
        #expect(evaluated.isEmpty)
        #expect(dictionary.loadEntries().isEmpty)

        // User edits in a non-chat editor and then clicks into another app/field.
        reading = .value("用 Swfit 写代码")
        service.prepare(observation: try observation("用 Swfit 写代码"), read: { reading })
        service.sample(at: 0.1)
        reading = .value("用 Swift 写代码")
        service.sample(at: 0.5)
        reading = .differentTarget
        service.sample(at: 1.2)
        await service.waitForPendingEvaluations()

        #expect(evaluated == [.init(original: "用 Swfit 写代码", edited: "用 Swift 写代码")])
        #expect(dictionary.loadRecords() == [.init(term: "Swift", source: .automatic)])
    }

    @Test func disabledDictionaryAndAbortedPasteNeverEvaluate() async throws {
        let dictionary = model()
        defer { dictionary.clear() }

        var calls = 0
        let service = MacCorrectionLearningService(dictionary: dictionary) { _ in
            calls += 1
            return ["Python"]
        }

        var reading: MacCorrectionLearningService.Reading = .value("我最近在学拍图")
        service.prepare(observation: try observation(), read: { reading })
        service.sample(at: 0.1)
        reading = .value("我最近在学 Python")
        service.sample(at: 0.4)
        service.abort()
        await service.waitForPendingEvaluations()
        #expect(calls == 0)

        service.prepare(observation: try observation(), read: { reading })
        reading = .value("我最近在学拍图")
        service.sample(at: 0.1)
        reading = .value("我最近在学 Python")
        service.sample(at: 0.4)
        dictionary.saveIsEnabled(false)
        service.finishCurrentObservation(at: 1.0, triggeredByCompletionKey: true)
        await service.waitForPendingEvaluations()
        #expect(calls == 0)
        #expect(dictionary.loadEntries().isEmpty)
    }
}
