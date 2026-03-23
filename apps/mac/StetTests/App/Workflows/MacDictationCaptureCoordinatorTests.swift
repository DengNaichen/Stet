#if os(macOS)
import Foundation
import Testing

@testable import Stet

@MainActor
@Suite("Mac Dictation Capture Coordinator", .serialized)
struct MacDictationCaptureCoordinatorTests {
    @Test func completedCaptureCopiesTextWithoutAutoPaste() async {
        let clipboard = TestClipboardService()
        let textInjection = TestTextInjectionService()
        let coordinator = MacDictationCaptureCoordinator(
            clipboardService: clipboard,
            textInjectionService: textInjection
        )

        let outcome = await coordinator.handleCompletedCapture(
            text: "hello",
            targetApplication: nil,
            settings: .init(
                shouldCopyToClipboard: true,
                shouldAutoPaste: false,
                shouldRevealPanelOnCapture: false
            ),
            showPanel: {}
        )

        #expect(outcome == .completed)
        #expect(clipboard.copiedTexts == ["hello"])
        #expect(clipboard.transientFlags == [false])
        #expect(textInjection.pasteTargets.isEmpty)
    }

    @Test func completedCaptureAutoPasteSucceedsAndCopiesInSamePath() async {
        let clipboard = TestClipboardService()
        let textInjection = TestTextInjectionService()
        textInjection.pasteResult = true
        let coordinator = MacDictationCaptureCoordinator(
            clipboardService: clipboard,
            textInjectionService: textInjection
        )
        var revealCount = 0

        let outcome = await coordinator.handleCompletedCapture(
            text: "hello",
            targetApplication: nil,
            settings: .init(
                shouldCopyToClipboard: false,
                shouldAutoPaste: true,
                shouldRevealPanelOnCapture: false
            ),
            showPanel: { revealCount += 1 }
        )

        #expect(outcome == .completed)
        #expect(clipboard.copiedTexts == ["hello"])
        #expect(clipboard.transientFlags == [true])
        #expect(textInjection.pasteTargets.count == 1)
        #expect(revealCount == 0)
    }

    @Test func completedCaptureCopiesAndPastesWhenEnabled() async {
        let clipboard = TestClipboardService()
        let textInjection = TestTextInjectionService()
        textInjection.pasteResult = true
        let coordinator = MacDictationCaptureCoordinator(
            clipboardService: clipboard,
            textInjectionService: textInjection
        )
        var revealCount = 0

        let outcome = await coordinator.handleCompletedCapture(
            text: "hello",
            targetApplication: nil,
            settings: .init(
                shouldCopyToClipboard: true,
                shouldAutoPaste: true,
                shouldRevealPanelOnCapture: true
            ),
            showPanel: { revealCount += 1 }
        )

        #expect(outcome == .completed)
        #expect(clipboard.copiedTexts == ["hello"])
        #expect(clipboard.transientFlags == [false])
        #expect(textInjection.pasteTargets.count == 1)
        #expect(revealCount == 0)
    }

    @Test
    func completedCaptureAutoPasteFailureWhenCopyIsEnabledRevealsPanelAndReturnsCompleted()
        async
    {
        let clipboard = TestClipboardService()
        let textInjection = TestTextInjectionService()
        textInjection.isAvailable = false
        textInjection.pasteResult = false
        let coordinator = MacDictationCaptureCoordinator(
            clipboardService: clipboard,
            textInjectionService: textInjection
        )
        var revealCount = 0

        let outcome = await coordinator.handleCompletedCapture(
            text: "hello",
            targetApplication: nil,
            settings: .init(
                shouldCopyToClipboard: true,
                shouldAutoPaste: true,
                shouldRevealPanelOnCapture: true
            ),
            showPanel: { revealCount += 1 }
        )

        #expect(outcome == .completed)
        #expect(clipboard.copiedTexts == ["hello"])
        #expect(clipboard.transientFlags == [false])
        #expect(textInjection.didRequestAccessIfNeeded)
        #expect(revealCount == 1)
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
            textInjectionService: textInjection
        )
        var revealCount = 0

        let outcome = await coordinator.handleCompletedCapture(
            text: "hello",
            targetApplication: nil,
            settings: .init(
                shouldCopyToClipboard: false,
                shouldAutoPaste: true,
                shouldRevealPanelOnCapture: true
            ),
            showPanel: { revealCount += 1 }
        )

        #expect(outcome == .clipboardPending)
        #expect(textInjection.didRequestAccessIfNeeded)
        #expect(revealCount == 1)
    }

    @Test func completedCaptureRevealsPanelWhenAutoPasteDisabled() async {
        let clipboard = TestClipboardService()
        let textInjection = TestTextInjectionService()
        let coordinator = MacDictationCaptureCoordinator(
            clipboardService: clipboard,
            textInjectionService: textInjection
        )
        var revealCount = 0

        let outcome = await coordinator.handleCompletedCapture(
            text: "hello",
            targetApplication: nil,
            settings: .init(
                shouldCopyToClipboard: false,
                shouldAutoPaste: false,
                shouldRevealPanelOnCapture: true
            ),
            showPanel: { revealCount += 1 }
        )

        #expect(outcome == .clipboardPending)
        #expect(clipboard.copiedTexts.isEmpty)
        #expect(textInjection.pasteTargets.isEmpty)
        #expect(revealCount == 1)
    }

    @Test func copyToClipboardCopiesText() {
        let clipboard = TestClipboardService()
        let textInjection = TestTextInjectionService()
        let coordinator = MacDictationCaptureCoordinator(
            clipboardService: clipboard,
            textInjectionService: textInjection
        )

        coordinator.copyToClipboard("snippet")

        #expect(clipboard.copiedTexts == ["snippet"])
        #expect(clipboard.transientFlags == [false])
    }

    @Test func completedCaptureSkipsClipboardWhenCopyAndPasteAreDisabled() async {
        let clipboard = TestClipboardService()
        let textInjection = TestTextInjectionService()
        let coordinator = MacDictationCaptureCoordinator(
            clipboardService: clipboard,
            textInjectionService: textInjection
        )

        let outcome = await coordinator.handleCompletedCapture(
            text: "hello",
            targetApplication: nil,
            settings: .init(
                shouldCopyToClipboard: false,
                shouldAutoPaste: false,
                shouldRevealPanelOnCapture: false
            ),
            showPanel: {}
        )

        #expect(outcome == .clipboardPending)
        #expect(clipboard.copiedTexts.isEmpty)
        #expect(textInjection.pasteTargets.isEmpty)
    }
}
#endif
