#if os(macOS)
    import Foundation
    import Testing

    @testable import Stet

    @MainActor
    @Suite("Dictionary View Model", .serialized)
    struct DictionaryViewModelTests {
        private func makeViewModel(
            defaults: UserDefaults
        ) throws -> (viewModel: DictionaryViewModel, model: DictionaryModel) {
            let dictionaryModel = DictionaryModel(
                modelContainer: try DictionaryModel.makeInMemoryModelContainer(),
                defaults: defaults
            )

            return (
                viewModel: DictionaryViewModel(dictionaryModel: dictionaryModel),
                model: dictionaryModel
            )
        }

        @Test func loadReflectsStoredEntriesAndEnabledState() throws {
            let defaults = TestSupport.makeUserDefaults()
            let subject = try makeViewModel(defaults: defaults)
            subject.model.saveIsEnabled(false)
            subject.model.saveEntries(["OpenAI", "Groq"])

            subject.viewModel.load()

            #expect(subject.viewModel.isEnabled == false)
            #expect(subject.viewModel.entries == ["OpenAI", "Groq"])
        }

        @Test func draftParsingAndAddEntriesNormalizeAndClearInput() throws {
            let defaults = TestSupport.makeUserDefaults()
            let subject = try makeViewModel(defaults: defaults)
            subject.viewModel.load()
            subject.viewModel.draft = " OpenAI, groq,\nOpenAI  ,  Naicheng Deng "

            #expect(subject.viewModel.parsedDraftEntries == ["OpenAI", "groq", "Naicheng Deng"])
            #expect(subject.viewModel.canAddDraftEntries)

            subject.viewModel.addDraftEntries()

            #expect(subject.viewModel.entries == ["OpenAI", "groq", "Naicheng Deng"])
            #expect(subject.viewModel.draft.isEmpty)
            #expect(subject.viewModel.canAddDraftEntries == false)
        }

        @Test func removeClearAndEnablePersistToModel() throws {
            let defaults = TestSupport.makeUserDefaults()
            let subject = try makeViewModel(defaults: defaults)
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
