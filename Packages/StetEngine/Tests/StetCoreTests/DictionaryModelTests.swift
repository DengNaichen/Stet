import Foundation
import Testing
@testable import StetCore

struct DictionaryModelTests {
    @Test func originsPersistAcrossReloadAndManualPromotion() {
        let defaults = UserDefaults(suiteName: "StetCoreTests.Origins.\(UUID().uuidString)")!
        let key = "dictionary.entries.\(UUID().uuidString)"
        defaults.set(["Swift"], forKey: key)
        let model = DictionaryModel(defaults: defaults, entriesKey: key)
        model.addAutomaticEntries(["Python", "swift"])
        // Keep the text-only sync format readable by previously released clients.
        #expect(defaults.stringArray(forKey: key) == ["Swift", "Python"])
        let reloaded = DictionaryModel(defaults: defaults, entriesKey: key)
        #expect(
            reloaded.loadRecords() == [
                .init(term: "Swift", source: .manual), .init(term: "Python", source: .automatic),
            ])
        _ = reloaded.addEntries(from: "python")
        #expect(
            model.loadRecords() == [
                .init(term: "Swift", source: .manual), .init(term: "python", source: .manual),
            ])
        model.clear()
    }

    @Test func removingAnEntryPreservesOtherOriginsAndDisabledDictionaryDoesNotLearn() {
        let defaults = UserDefaults(suiteName: "StetCoreTests.Origins.\(UUID().uuidString)")!
        let model = DictionaryModel(defaults: defaults, entriesKey: "dictionary.entries.\(UUID().uuidString)")
        model.addAutomaticEntries(["Python", "Swift"])
        _ = model.removeEntry("Swift")
        #expect(model.loadRecords() == [.init(term: "Python", source: .automatic)])
        model.saveIsEnabled(false)
        model.addAutomaticEntries(["Rust"])
        #expect(model.loadEntries() == ["Python"])
        model.clear()
    }
    @Test func wordsNormalizeWhitespaceAndDeduplicate() {
        #expect(
            DictionaryModel.words(from: " OpenAI, groq,\nOpenAI  ,  Naicheng Deng ")
                == ["OpenAI", "groq", "Naicheng Deng"]
        )
    }

    @Test func addRemoveAndClearPersistEntries() {
        let defaults = UserDefaults(suiteName: "StetCoreTests.Dictionary.\(UUID().uuidString)")!
        let entriesKey = "dictionary.entries.\(UUID().uuidString)"
        let enabledKey = "dictionary.enabled.\(UUID().uuidString)"
        let subject = DictionaryModel(
            defaults: defaults,
            entriesKey: entriesKey,
            enabledKey: enabledKey
        )

        #expect(subject.addEntries(from: "OpenAI, Groq, openai") == ["OpenAI", "Groq"])
        #expect(subject.removeEntry("groq") == ["OpenAI"])
        subject.clear()
        #expect(subject.loadEntries().isEmpty)
    }

    @Test func enabledFlagPersistsInDefaults() {
        let defaults = UserDefaults(suiteName: "StetCoreTests.Enabled.\(UUID().uuidString)")!
        let subject = DictionaryModel(
            defaults: defaults,
            entriesKey: "dictionary.entries.\(UUID().uuidString)",
            enabledKey: "dictionary.enabled.\(UUID().uuidString)"
        )

        #expect(subject.loadIsEnabled() == true)
        subject.saveIsEnabled(false)
        #expect(subject.loadIsEnabled() == false)
    }

    @Test func localCacheFallbackReturnsCachedEntriesWhenCloudIsEmpty() {
        let defaults = UserDefaults(suiteName: "StetCoreTests.Cache.\(UUID().uuidString)")!
        let entriesKey = "dictionary.entries.\(UUID().uuidString)"
        defaults.set(["Cursor", "OpenAI"], forKey: entriesKey)

        let subject = DictionaryModel(
            defaults: defaults,
            entriesKey: entriesKey,
            enabledKey: "dictionary.enabled.\(UUID().uuidString)"
        )

        #expect(subject.loadEntries() == ["Cursor", "OpenAI"])
    }
}
