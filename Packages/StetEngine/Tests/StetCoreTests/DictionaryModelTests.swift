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

    @Test func importMergesManualTermsAndReportsDuplicates() throws {
        let defaults = UserDefaults(suiteName: "StetCoreTests.Import.\(UUID().uuidString)")!
        let subject = DictionaryModel(
            defaults: defaults,
            entriesKey: "dictionary.entries.\(UUID().uuidString)"
        )
        subject.addAutomaticEntries(["python"])
        let result = try subject.importEntries(from: "Python, Stet\nCursor")
        #expect(result.addedCount == 2)
        #expect(result.skippedCount == 1)
        #expect(
            subject.loadRecords() == [
                .init(term: "python", source: .automatic),
                .init(term: "Stet", source: .manual),
                .init(term: "Cursor", source: .manual),
            ])
        subject.clear()
    }

    @Test func importRejectsEmptyTextAndOversizedFiles() throws {
        let defaults = UserDefaults(suiteName: "StetCoreTests.ImportLimits.\(UUID().uuidString)")!
        let subject = DictionaryModel(
            defaults: defaults,
            entriesKey: "dictionary.entries.\(UUID().uuidString)"
        )
        #expect(throws: DictionaryImportError.empty) {
            try subject.importEntries(from: "  , \n ")
        }
        let oversized = Data(repeating: 0x61, count: DictionaryModel.maximumImportFileByteCount + 1)
        #expect(throws: DictionaryImportError.fileTooLarge(byteCount: oversized.count)) {
            _ = try DictionaryModel.importText(from: oversized)
        }
        let text = try DictionaryModel.importText(from: Data("\u{FEFF}OpenAI, Groq".utf8))
        #expect(DictionaryModel.words(from: text) == ["OpenAI", "Groq"])
        let oversizedDictionary = String(repeating: "a", count: DictionaryModel.maximumStoredUTF8ByteCount)
        #expect(throws: DictionaryImportError.dictionaryWouldExceedLimit) {
            try subject.importEntries(from: oversizedDictionary)
        }
        subject.clear()
    }
}
