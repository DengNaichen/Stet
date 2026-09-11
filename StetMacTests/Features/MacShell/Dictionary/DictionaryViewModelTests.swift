#if os(macOS)
    import Foundation
    import Testing
    import StetCore

    @testable import Stet

    @MainActor
    @Suite("Dictionary View Model", .serialized)
    struct DictionaryViewModelTests {
        @Test func entrySourceIsVisibleAndManualAddPromotesAutomaticEntry() {
            let subject = makeViewModel(defaults: TestSupport.makeUserDefaults())
            defer { subject.model.clear() }
            subject.model.addAutomaticEntries(["python"])
            subject.viewModel.load()
            #expect(subject.viewModel.source(for: "python") == .automatic)
            subject.viewModel.draft = "Python"
            subject.viewModel.addDraftEntries()
            #expect(subject.viewModel.entries == ["Python"])
            #expect(subject.viewModel.source(for: "Python") == .manual)
        }
        @Test func manualEditorPromotesOnlySavedEntries() {
            let subject = makeViewModel(defaults: TestSupport.makeUserDefaults())
            defer { subject.model.clear() }
            subject.model.addAutomaticEntries(["python", "Swift"])
            subject.viewModel.load()
            subject.viewModel.saveEntries(from: "Python", replacing: "python")
            #expect(subject.viewModel.entries == ["Python", "Swift"])
            #expect(subject.viewModel.source(for: "Python") == .manual)
            #expect(subject.viewModel.source(for: "Swift") == .automatic)
            subject.viewModel.saveEntries(from: "Swift", replacing: nil)
            #expect(subject.viewModel.source(for: "Swift") == .manual)
        }

        private func makeViewModel(
            defaults: UserDefaults
        ) -> (viewModel: DictionaryViewModel, model: DictionaryModel) {
            let entriesKey = "dictionary.entries.\(UUID().uuidString)"
            let enabledKey = "dictionary.enabled.\(UUID().uuidString)"
            let dictionaryModel = DictionaryModel(
                defaults: defaults,
                entriesKey: entriesKey,
                enabledKey: enabledKey
            )

            return (
                viewModel: DictionaryViewModel(dictionaryModel: dictionaryModel),
                model: dictionaryModel
            )
        }

        @Test func editingPreservesOtherEntriesAndNormalizesReplacement() {
            let subject = makeViewModel(defaults: TestSupport.makeUserDefaults())
            subject.model.saveEntries(["OpenAI", "Groq", "Stet"])
            subject.viewModel.load()
            subject.viewModel.saveEntries(from: "  Google  , Stet", replacing: "Groq")
            #expect(subject.viewModel.entries == ["OpenAI", "Google", "Stet"])
            subject.viewModel.saveEntries(from: "  ", replacing: "Google")
            #expect(subject.model.loadEntries() == ["OpenAI", "Google", "Stet"])
        }

        @Test func loadReflectsStoredEntriesAndEnabledState() {
            let defaults = TestSupport.makeUserDefaults()
            let subject = makeViewModel(defaults: defaults)
            subject.model.saveIsEnabled(false)
            subject.model.saveEntries(["OpenAI", "Groq"])

            subject.viewModel.load()

            #expect(subject.viewModel.isEnabled == false)
            #expect(subject.viewModel.entries == ["OpenAI", "Groq"])
        }

        @Test func draftParsingAndAddEntriesNormalizeAndClearInput() {
            let defaults = TestSupport.makeUserDefaults()
            let subject = makeViewModel(defaults: defaults)
            subject.viewModel.load()
            subject.viewModel.draft = " OpenAI, groq,\nOpenAI  ,  Naicheng Deng "

            #expect(subject.viewModel.parsedDraftEntries == ["OpenAI", "groq", "Naicheng Deng"])
            #expect(subject.viewModel.canAddDraftEntries)

            subject.viewModel.addDraftEntries()

            #expect(subject.viewModel.entries == ["OpenAI", "groq", "Naicheng Deng"])
            #expect(subject.viewModel.draft.isEmpty)
            #expect(subject.viewModel.canAddDraftEntries == false)
        }

        @Test func removeClearAndEnablePersistToModel() {
            let defaults = TestSupport.makeUserDefaults()
            let subject = makeViewModel(defaults: defaults)
            subject.model.saveEntries(["OpenAI", "Groq"])
            subject.viewModel.load()

            subject.viewModel.setEnabled(false)
            subject.viewModel.removeEntry("groq")

            #expect(subject.viewModel.isEnabled == false)
            #expect(subject.viewModel.entries == ["OpenAI"])

            subject.viewModel.clearEntries()

            #expect(subject.viewModel.entries.isEmpty)
            #expect(subject.model.loadEntries().isEmpty)
            #expect(subject.model.loadIsEnabled() == false)
        }

        @Test func importFromTextFileMergesAndReportsCounts() throws {
            let subject = makeViewModel(defaults: TestSupport.makeUserDefaults())
            defer { subject.model.clear() }
            subject.model.addAutomaticEntries(["python"])
            subject.viewModel.load()
            let url = TestSupport.temporaryFileURL("glossary", ext: "txt")
            try Data("Python, Stet\nCursor\n".utf8).write(to: url)
            subject.viewModel.importEntries(from: url)
            #expect(subject.viewModel.entries == ["python", "Stet", "Cursor"])
            #expect(subject.viewModel.source(for: "python") == .automatic)
            #expect(subject.viewModel.source(for: "Stet") == .manual)
            #expect(subject.viewModel.importAlert == .success(added: 2, skipped: 1))
        }
    }
#endif
