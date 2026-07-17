#if os(macOS)
    import Combine
    import Foundation
    import StetCore

    @MainActor
    final class DictionaryViewModel: ObservableObject {
        private let dictionaryModel: DictionaryModel
        private var syncObserver: NSObjectProtocol?

        @Published private(set) var isEnabled = true
        @Published private(set) var entries: [String] = []
        @Published var draft = ""

        init(dictionaryModel: DictionaryModel = DictionaryModel()) {
            self.dictionaryModel = dictionaryModel
            self.syncObserver = NotificationCenter.default.addObserver(
                forName: .dictionaryDidSync,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                self.entries = self.dictionaryModel.loadEntries()
            }
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
