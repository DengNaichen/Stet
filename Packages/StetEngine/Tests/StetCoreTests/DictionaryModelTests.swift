import Foundation
import Testing
@testable import StetCore

struct DictionaryModelTests {
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
