#if os(macOS)
import Foundation
import Testing

@testable import airType

@MainActor
@Suite("Mac Dictation Capture Coordinator", .serialized)
struct MacDictationCaptureCoordinatorTests {
    @Test func loadHistoryAppliesRetentionPolicy() async {
        let defaults = TestSupport.makeUserDefaults()
        defaults.set(HistoryRetentionPeriod.sevenDays.rawValue, forKey: MacPreferences.historyRetentionPeriod)
        let settingsStore = DictationSettingsStore(defaults: defaults, secretStore: TestSecretStore())
        let now = Date(timeIntervalSince1970: 1_000_000)
        let historyStore = TestHistoryStore(records: [
            TranscriptionRecord(text: "recent", createdAt: now.addingTimeInterval(-60)),
            TranscriptionRecord(text: "old", createdAt: now.addingTimeInterval(-9 * 24 * 60 * 60)),
        ])
        let coordinator = MacDictationCaptureCoordinator(
            clipboardService: TestClipboardService(),
            textInjectionService: TestTextInjectionService(),
            historyStore: historyStore,
            settingsStore: settingsStore,
            nowProvider: { now }
        )

        let history = await coordinator.loadHistory()

        #expect(history.map(\.text) == ["recent"])
        #expect(await historyStore.loadHistory().map(\.text) == ["recent"])
    }

    @Test func prepareCaptureCapsHistoryAtMaximumCount() async {
        let defaults = TestSupport.makeUserDefaults()
        defaults.set(HistoryRetentionPeriod.forever.rawValue, forKey: MacPreferences.historyRetentionPeriod)
        let settingsStore = DictationSettingsStore(defaults: defaults, secretStore: TestSecretStore())
        let history = (0..<300).map {
            TranscriptionRecord(
                text: "item-\($0)",
                createdAt: Date(timeIntervalSince1970: TimeInterval(1_000_000 - $0))
            )
        }
        let coordinator = MacDictationCaptureCoordinator(
            clipboardService: TestClipboardService(),
            textInjectionService: TestTextInjectionService(),
            historyStore: TestHistoryStore(),
            settingsStore: settingsStore,
            nowProvider: { Date(timeIntervalSince1970: 1_000_000) }
        )

        let prepared = await coordinator.prepareCapture(
            text: "latest",
            metadata: .init(kind: .dictation),
            existingHistory: history
        )

        #expect(prepared.history.count == 250)
        #expect(prepared.history.first?.text == "latest")
    }

    @Test func completedCaptureCopiesAndPastesWhenEnabled() async {
        let clipboard = TestClipboardService()
        let textInjection = TestTextInjectionService()
        textInjection.pasteResult = true
        let coordinator = MacDictationCaptureCoordinator(
            clipboardService: clipboard,
            textInjectionService: textInjection,
            historyStore: TestHistoryStore()
        )

        let outcome = await coordinator.handleCompletedCapture(
            text: "hello",
            existingHistory: [],
            metadata: .init(kind: .dictation),
            targetApplication: nil,
            settings: .init(
                shouldCopyToClipboard: true,
                shouldAutoPaste: true,
                shouldRevealPanelOnCapture: true
            ),
            showPanel: {}
        )

        #expect(clipboard.copiedTexts == ["hello"])
        #expect(outcome.copiedRecordID != nil)
        #expect(outcome.history.first?.text == "hello")
    }

    @Test func completedCaptureRequestsAccessibilityWhenPasteUnavailable() async {
        let clipboard = TestClipboardService()
        let textInjection = TestTextInjectionService()
        textInjection.isAvailable = false
        textInjection.accessState = .init(
            hasAccessibilityAccess: false,
            hasPostEventAccess: false
        )
        textInjection.pasteResult = false
        let coordinator = MacDictationCaptureCoordinator(
            clipboardService: clipboard,
            textInjectionService: textInjection,
            historyStore: TestHistoryStore()
        )
        var revealCount = 0

        _ = await coordinator.handleCompletedCapture(
            text: "hello",
            existingHistory: [],
            metadata: .init(kind: .dictation),
            targetApplication: nil,
            settings: .init(
                shouldCopyToClipboard: false,
                shouldAutoPaste: true,
                shouldRevealPanelOnCapture: true
            ),
            showPanel: { revealCount += 1 }
        )

        #expect(textInjection.didRequestAccessIfNeeded)
        #expect(revealCount == 1)
    }
}
#endif
