#if os(macOS)
import AppKit
import Foundation

@MainActor
final class MacDictationCaptureCoordinator {
    private enum Constants {
        static let maxHistoryCount = 250
    }

    struct CaptureSettings {
        let shouldCopyToClipboard: Bool
        let shouldAutoPaste: Bool
        let shouldRevealPanelOnCapture: Bool
    }

    struct CaptureOutcome {
        let history: [TranscriptionRecord]
        let copiedRecordID: UUID?
    }

    struct PreparedCapture {
        let record: TranscriptionRecord
        let history: [TranscriptionRecord]
    }

    private let clipboardService: any ClipboardService
    private let textInjectionService: any TextInjectionService
    private let historyStore: any TranscriptionHistoryStore
    private let settingsStore: DictationSettingsStore
    private let nowProvider: @Sendable () -> Date

    init(
        clipboardService: any ClipboardService,
        textInjectionService: any TextInjectionService,
        historyStore: any TranscriptionHistoryStore,
        settingsStore: DictationSettingsStore = DictationSettingsStore(),
        nowProvider: @escaping @Sendable () -> Date = Date.init
    ) {
        self.clipboardService = clipboardService
        self.textInjectionService = textInjectionService
        self.historyStore = historyStore
        self.settingsStore = settingsStore
        self.nowProvider = nowProvider
    }

    func loadHistory() async -> [TranscriptionRecord] {
        let records = retainedHistory(await historyStore.loadHistory())
        await historyStore.saveHistory(records)
        return records
    }

    func persistHistory(_ records: [TranscriptionRecord]) {
        let retainedRecords = retainedHistory(records)
        Task { [historyStore] in
            await historyStore.saveHistory(retainedRecords)
        }
    }

    func prepareCapture(
        text: String,
        metadata: TranscriptionRecordMetadata,
        existingHistory: [TranscriptionRecord]
    ) async -> PreparedCapture {
        let record = TranscriptionRecord(text: text, metadata: metadata)
        let updatedHistory = Array(([record] + retainedHistory(existingHistory)).prefix(Constants.maxHistoryCount))
        await historyStore.saveHistory(updatedHistory)
        return PreparedCapture(record: record, history: updatedHistory)
    }

    func handleCompletedCapture(
        text: String,
        existingHistory: [TranscriptionRecord],
        metadata: TranscriptionRecordMetadata,
        targetApplication: NSRunningApplication?,
        settings: CaptureSettings,
        showPanel: @escaping @MainActor () -> Void
    ) async -> CaptureOutcome {
        let prepared = await prepareCapture(
            text: text,
            metadata: metadata,
            existingHistory: existingHistory
        )

        var copiedRecordID: UUID?

        if settings.shouldCopyToClipboard || settings.shouldAutoPaste {
            clipboardService.copy(prepared.record.text)
            copiedRecordID = prepared.record.id
        }

        if settings.shouldAutoPaste {
            let didPaste = await textInjectionService.pasteClipboard(into: targetApplication)

            if !didPaste && !textInjectionService.isAvailable {
                textInjectionService.requestAccessIfNeeded()
            }

            if settings.shouldRevealPanelOnCapture && !didPaste {
                showPanel()
            }
        } else if settings.shouldRevealPanelOnCapture {
            showPanel()
        }

        return CaptureOutcome(history: prepared.history, copiedRecordID: copiedRecordID)
    }

    private func retainedHistory(_ records: [TranscriptionRecord]) -> [TranscriptionRecord] {
        let retention = settingsStore.loadHistoryRetentionPeriod()
        let now = nowProvider()
        return records
            .filter { retention.includes($0.createdAt, relativeTo: now) }
            .sorted { $0.createdAt > $1.createdAt }
    }
}
#endif
