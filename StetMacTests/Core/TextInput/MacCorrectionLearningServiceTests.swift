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

    private func observation(_ inserted: String = "拍图") throws -> CorrectionObservation {
        try #require(
            CorrectionObservation(
                before: "", selection: .init(location: 0, length: 0), inserted: inserted, startedAt: 0))
    }

    @Test func fieldEditsReachTheDictionaryWithAutomaticSource() throws {
        let dictionary = model()
        defer { dictionary.clear() }
        let service = MacCorrectionLearningService(dictionary: dictionary)
        var field = "拍图"
        service.prepare(observation: try observation(), read: { .value(field) })
        service.sample(at: 0.1)
        field = "Python"
        service.sample(at: 0.2)
        #expect(dictionary.loadEntries().isEmpty)
        service.sample(at: 1.3)
        #expect(dictionary.loadRecords() == [.init(term: "Python", source: .automatic)])
        service.stop()
    }

    @Test func changingTargetOrStartingANewObservationCannotTeachAnOldResult() throws {
        let dictionary = model()
        defer { dictionary.clear() }
        let service = MacCorrectionLearningService(dictionary: dictionary)
        var reading: MacCorrectionLearningService.Reading = .value("拍图")
        service.prepare(observation: try observation(), read: { reading })
        service.sample(at: 0.1)
        reading = .value("Python")
        service.sample(at: 0.2)
        reading = .differentTarget
        service.sample(at: 1.3)
        reading = .value("Python")
        service.sample(at: 2)
        #expect(dictionary.loadEntries().isEmpty)

        service.prepare(observation: try observation("Swfit"), read: { reading })
        reading = .value("Swfit")
        service.sample(at: 0.1)
        reading = .value("Swift")
        service.sample(at: 0.2, finishing: true)
        #expect(dictionary.loadRecords() == [.init(term: "Swift", source: .automatic)])
    }

    @Test func disabledDictionaryAndUnavailableFinalReadDoNotLearn() throws {
        let dictionary = model()
        defer { dictionary.clear() }
        let service = MacCorrectionLearningService(dictionary: dictionary)
        var reading: MacCorrectionLearningService.Reading = .value("拍图")
        service.prepare(observation: try observation(), read: { reading })
        service.sample(at: 0.1)
        reading = .value("Python")
        service.sample(at: 0.2)
        reading = .unavailable
        service.sample(at: 0.3, finishing: true)
        #expect(dictionary.loadEntries().isEmpty)
        service.prepare(observation: try observation(), read: { reading })
        reading = .value("拍图")
        service.sample(at: 0.1)
        dictionary.saveIsEnabled(false)
        reading = .value("Python")
        service.sample(at: 2, finishing: true)
        #expect(dictionary.loadEntries().isEmpty)
    }
}
