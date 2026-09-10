#if os(macOS)
    import Foundation
    import Testing
    import StetCore

    @testable import Stet

    @MainActor
    @Suite("Dictionary View Model", .serialized)
    struct DictionaryViewModelTests {
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
    }
#endif
