#if os(macOS)
    import Combine
    import Foundation

    @MainActor
    final class DictionaryViewModel: ObservableObject {
        private let dictionaryModel: DictionaryModel

        @Published private(set) var isEnabled = true
        @Published private(set) var entries: [String] = []
        @Published var draft = ""

        init(dictionaryModel: DictionaryModel = DictionaryModel()) {
            self.dictionaryModel = dictionaryModel
        }

        var parsedDraftEntries: [String] {
            DictionaryModel.words(from: draft)
        }

        var canAddDraftEntries: Bool {
            !parsedDraftEntries.isEmpty
        }

        func load() {
            isEnabled = dictionaryModel.loadIsEnabled()
            entries = dictionaryModel.loadEntries()
        }

        func setEnabled(_ enabled: Bool) {
            isEnabled = enabled
            dictionaryModel.saveIsEnabled(enabled)
        }

        func addDraftEntries() {
            guard canAddDraftEntries else { return }

            entries = dictionaryModel.addEntries(from: draft)
            draft = ""
        }

        func removeEntry(_ entry: String) {
            entries = dictionaryModel.removeEntry(entry)
        }

        func clearEntries() {
            dictionaryModel.clear()
            entries = []
        }
    }
#endif
