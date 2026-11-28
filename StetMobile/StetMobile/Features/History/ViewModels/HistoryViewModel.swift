import Combine
import Foundation
import StetCore
import SwiftData

@MainActor
protocol HistoryEntriesStore: AnyObject {
    func fetchRecent(limit: Int) throws -> [HistoryEntry]
    func deleteAll() throws
}

extension DictationHistoryService: HistoryEntriesStore {}

@MainActor
final class ModelContainerHistoryStore: HistoryEntriesStore {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    func fetchRecent(limit: Int) throws -> [HistoryEntry] {
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<HistoryEntry>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor)
    }

    func deleteAll() throws {
        let context = ModelContext(container)
        try context.delete(model: HistoryEntry.self)
        try context.save()
    }
}

struct HistoryItem: Identifiable, Equatable, Sendable {
    let id: UUID
    let timestamp: Date
    let rawText: String
    let llmText: String?
    let finalText: String?
    let targetBundleID: String?
    let targetAppName: String?

    init(entry: HistoryEntry) {
        self.id = entry.id
        self.timestamp = entry.timestamp
        self.rawText = entry.rawText
        self.llmText = entry.llmText
        self.finalText = entry.finalText
        self.targetBundleID = entry.targetBundleID
        self.targetAppName = entry.targetAppName
    }

    var displayText: String {
        if let finalText = Self.nonEmpty(finalText) {
            return finalText
        }
        if let llmText = Self.nonEmpty(llmText) {
            return llmText
        }
        return rawText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedRawText: String {
        rawText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isRewritten: Bool {
        Self.nonEmpty(llmText) != nil
    }

    var hasDistinctRawText: Bool {
        !trimmedRawText.isEmpty && trimmedRawText != displayText
    }

    var appDisplayName: String? {
        if let appName = Self.nonEmpty(targetAppName) {
            return appName
        }
        return Self.nonEmpty(targetBundleID)
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

@MainActor
final class HistoryViewModel: ObservableObject {
    @Published private(set) var entries: [HistoryItem] = []
    @Published private(set) var usageSummary: DictationUsageSummary = .empty
    @Published private(set) var activityDetails: [Date: DictationDailySummary] = [:]
    @Published var searchText = ""
    @Published private(set) var loadError: String?

    private let historyStore: any HistoryEntriesStore
    private let statsModel: DictationStatsModel
    private let fetchLimit: Int
    private var cancellables: Set<AnyCancellable> = []

    init(
        historyStore: (any HistoryEntriesStore)? = nil,
        statsModel: DictationStatsModel = .shared,
        notificationCenter: NotificationCenter = .default,
        fetchLimit: Int = 300
    ) {
        self.historyStore = historyStore ?? DictationHistoryService.shared
        self.statsModel = statsModel
        self.fetchLimit = fetchLimit

        notificationCenter.publisher(for: .stetCloudDataDidChange)
            .sink { [weak self] _ in
                self?.reload()
            }
            .store(in: &cancellables)
    }

    convenience init(
        modelContainer: ModelContainer,
        notificationCenter: NotificationCenter = .default,
        fetchLimit: Int = 300
    ) {
        self.init(
            historyStore: ModelContainerHistoryStore(container: modelContainer),
            statsModel: DictationStatsModel(modelContainer: modelContainer),
            notificationCenter: notificationCenter,
            fetchLimit: fetchLimit
        )
    }

    var filteredEntries: [HistoryItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return entries }
        return entries.filter { item in
            item.displayText.localizedCaseInsensitiveContains(query)
                || item.rawText.localizedCaseInsensitiveContains(query)
                || (item.llmText?.localizedCaseInsensitiveContains(query) == true)
                || (item.targetAppName?.localizedCaseInsensitiveContains(query) == true)
                || (item.targetBundleID?.localizedCaseInsensitiveContains(query) == true)
        }
    }

    func reload() {
        usageSummary = statsModel.usageSummary()
        activityDetails = statsModel.activityDetails()
        do {
            let fetched = try historyStore.fetchRecent(limit: fetchLimit)
            entries = fetched.map(HistoryItem.init(entry:))
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    func deleteAll() {
        do {
            try historyStore.deleteAll()
            entries = []
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }
}
