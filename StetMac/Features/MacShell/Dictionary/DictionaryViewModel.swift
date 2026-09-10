#if os(macOS)
    import Combine
    import Foundation
    import StetCore

    @MainActor
    final class DictionaryViewModel: ObservableObject {
        private let dictionaryModel: DictionaryModel
        private var syncObserver: NSObjectProtocol?

        @Published private(set) var isEnabled = true
        @Published private(set) var records: [GlossaryEntry] = []
        var entries: [String] { records.map(\.term) }

        func source(for term: String) -> GlossaryEntry.Source {
            records.first { $0.term == term }?.source ?? .manual
        }
        @Published var draft = ""

        init(dictionaryModel: DictionaryModel = DictionaryModel()) {
            self.dictionaryModel = dictionaryModel
            self.syncObserver = NotificationCenter.default.addObserver(
                forName: .dictionaryDidSync,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                self.records = self.dictionaryModel.loadRecords()
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
            records = dictionaryModel.loadRecords()
        }

        func setEnabled(_ enabled: Bool) {
            isEnabled = enabled
            dictionaryModel.saveIsEnabled(enabled)
        }

        func addDraftEntries() {
            guard canAddDraftEntries else { return }

            _ = dictionaryModel.addEntries(from: draft)
            records = dictionaryModel.loadRecords()
            draft = ""
        }

        func canSaveEntries(from text: String) -> Bool {
            !DictionaryModel.words(from: text).isEmpty
        }

        func saveEntries(from text: String, replacing original: String?) {
            let additions = DictionaryModel.words(from: text)
            guard !additions.isEmpty else { return }
            var updated = dictionaryModel.loadEntries()
            if let original, let index = updated.firstIndex(of: original) {
                updated.replaceSubrange(index...index, with: additions)
            } else {
                updated.append(contentsOf: additions)
            }
            dictionaryModel.saveEntries(updated)
            _ = dictionaryModel.addEntries(from: text)
            records = dictionaryModel.loadRecords()
        }

        func removeEntry(_ entry: String) {
            _ = dictionaryModel.removeEntry(entry)
            records = dictionaryModel.loadRecords()
        }

        func clearEntries() {
            dictionaryModel.clear()
            records = []
        }
    }
#endif
