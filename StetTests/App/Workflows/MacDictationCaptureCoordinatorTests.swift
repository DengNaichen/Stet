#if os(macOS)
    import Foundation
    import Testing

    @testable import Stet

    @MainActor
    @Suite("Mac Dictation Capture Coordinator", .serialized)
    struct MacDictationCaptureCoordinatorTests {
        private func makeCoordinator(
            clipboard: TestClipboardService,
            textInjection: TestTextInjectionService,
            frontmostBundleIdentifier: String? = nil
        ) -> MacDictationCaptureCoordinator {
            MacDictationCaptureCoordinator(
                clipboardService: clipboard,
                textInjectionService: textInjection,
                frontmostBundleIdentifierProvider: { frontmostBundleIdentifier }
            )
        }

        @Test func completedCaptureCopiesTextWithoutAutoPaste() async {
            let clipboard = TestClipboardService()
            let textInjection = TestTextInjectionService()
            let coordinator = makeCoordinator(clipboard: clipboard, textInjection: textInjection)

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
            let coordinator = makeCoordinator(clipboard: clipboard, textInjection: textInjection)
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
            let coordinator = makeCoordinator(clipboard: clipboard, textInjection: textInjection)
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
            let coordinator = makeCoordinator(clipboard: clipboard, textInjection: textInjection)
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

            #expect(outcome == .failed(.autoPastePermissionMissing))
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
            let coordinator = makeCoordinator(clipboard: clipboard, textInjection: textInjection)
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

            #expect(outcome == .failed(.autoPastePermissionMissing))
            #expect(clipboard.copiedTexts == ["hello", "hello"])
            #expect(clipboard.transientFlags == [true, false])
            #expect(textInjection.didRequestAccessIfNeeded)
            #expect(revealCount == 1)
        }

        @Test func completedCaptureRevealsPanelWhenAutoPasteDisabled() async {
            let clipboard = TestClipboardService()
            let textInjection = TestTextInjectionService()
            let coordinator = makeCoordinator(clipboard: clipboard, textInjection: textInjection)
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
            let coordinator = makeCoordinator(clipboard: clipboard, textInjection: textInjection)

            coordinator.copyToClipboard("snippet")

            #expect(clipboard.copiedTexts == ["snippet"])
            #expect(clipboard.transientFlags == [false])
        }

        @Test func completedCaptureTreatsVerificationUnavailableAsDistinctFailure() async {
            let clipboard = TestClipboardService()
            let textInjection = TestTextInjectionService()
            textInjection.pasteOutcome = .eventPostedVerificationUnavailable
            let coordinator = makeCoordinator(clipboard: clipboard, textInjection: textInjection)
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

            #expect(outcome == .failed(.pasteVerificationUnavailable))
            #expect(clipboard.copiedTexts == ["hello", "hello"])
            #expect(clipboard.transientFlags == [true, false])
            #expect(textInjection.pasteTargets.count == 1)
            #expect(revealCount == 0)
        }

        @Test func vsCodeVerificationUnavailableCompletesWithoutFallbackOrPanel() async {
            let clipboard = TestClipboardService()
            let textInjection = TestTextInjectionService()
            textInjection.pasteOutcome = .eventPostedVerificationUnavailableInTextInput
            let coordinator = makeCoordinator(
                clipboard: clipboard,
                textInjection: textInjection,
                frontmostBundleIdentifier: "com.microsoft.VSCode"
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

            #expect(outcome == .completed)
            #expect(clipboard.copiedTexts == ["hello"])
            #expect(clipboard.transientFlags == [true])
            #expect(textInjection.pasteTargets.count == 1)
            #expect(textInjection.didRequestAccessIfNeeded == false)
            #expect(revealCount == 0)
        }

        @Test func vsCodeVerificationFailureCompletesWithoutFallbackOrPanel() async {
            let clipboard = TestClipboardService()
            let textInjection = TestTextInjectionService()
            textInjection.pasteOutcome = .verificationFailed
            let coordinator = makeCoordinator(
                clipboard: clipboard,
                textInjection: textInjection,
                frontmostBundleIdentifier: "com.microsoft.VSCode"
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

            #expect(outcome == .completed)
            #expect(clipboard.copiedTexts == ["hello"])
            #expect(clipboard.transientFlags == [true])
            #expect(textInjection.pasteTargets.count == 1)
            #expect(textInjection.didRequestAccessIfNeeded == false)
            #expect(revealCount == 0)
        }

        @Test func vsCodeGenericVerificationUnavailableCompletesWithoutFallbackOrPanel() async {
            let clipboard = TestClipboardService()
            let textInjection = TestTextInjectionService()
            textInjection.pasteOutcome = .eventPostedVerificationUnavailable
            let coordinator = makeCoordinator(
                clipboard: clipboard,
                textInjection: textInjection,
                frontmostBundleIdentifier: "com.microsoft.VSCode"
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

            #expect(outcome == .completed)
            #expect(clipboard.copiedTexts == ["hello"])
            #expect(clipboard.transientFlags == [true])
            #expect(textInjection.pasteTargets.count == 1)
            #expect(textInjection.didRequestAccessIfNeeded == false)
            #expect(revealCount == 0)
        }

        @Test func otherOptimisticAppsVerificationUnavailableCompleteWithoutFallbackOrPanel()
            async
        {
            let bundleIdentifiers = [
                "com.openai.codex",
                "com.google.antigravity",
                "dev.zed.app",
                "dev.zed.Zed",
            ]

            for bundleIdentifier in bundleIdentifiers {
                let clipboard = TestClipboardService()
                let textInjection = TestTextInjectionService()
                textInjection.pasteOutcome = .eventPostedVerificationUnavailableInTextInput
                let coordinator = makeCoordinator(
                    clipboard: clipboard,
                    textInjection: textInjection,
                    frontmostBundleIdentifier: bundleIdentifier
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

                #expect(outcome == .completed, "Expected \(bundleIdentifier) to complete")
                #expect(clipboard.copiedTexts == ["hello"], "Expected \(bundleIdentifier) to copy once")
                #expect(clipboard.transientFlags == [true], "Expected \(bundleIdentifier) to use transient copy")
                #expect(textInjection.pasteTargets.count == 1, "Expected \(bundleIdentifier) to attempt one paste")
                #expect(
                    textInjection.didRequestAccessIfNeeded == false,
                    "Expected \(bundleIdentifier) not to request access")
                #expect(revealCount == 0, "Expected \(bundleIdentifier) not to reveal panel")
            }
        }

        @Test func nonProfiledGenericVerificationUnavailableFallsBackToClipboardRecovery() async {
            let clipboard = TestClipboardService()
            let textInjection = TestTextInjectionService()
            textInjection.pasteOutcome = .eventPostedVerificationUnavailable
            let coordinator = makeCoordinator(
                clipboard: clipboard,
                textInjection: textInjection,
                frontmostBundleIdentifier: "com.apple.TextEdit"
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

            #expect(outcome == .failed(.pasteVerificationUnavailable))
            #expect(clipboard.copiedTexts == ["hello", "hello"])
            #expect(clipboard.transientFlags == [true, false])
            #expect(textInjection.didRequestAccessIfNeeded == false)
            #expect(revealCount == 0)
        }

        @Test func verificationUnavailableRequestsMissingAccessibilityAccess() async {
            let clipboard = TestClipboardService()
            let textInjection = TestTextInjectionService()
            textInjection.accessState = .init(
                hasAccessibilityAccess: false,
                hasPostEventAccess: true
            )
            textInjection.pasteOutcome = .eventPostedVerificationUnavailable
            let coordinator = makeCoordinator(clipboard: clipboard, textInjection: textInjection)

            let outcome = await coordinator.handleCompletedCapture(
                text: "hello",
                targetApplication: nil,
                settings: .init(
                    shouldCopyToClipboard: false,
                    shouldAutoPaste: true,
                    shouldRevealPanelOnCapture: false
                ),
                showPanel: {}
            )

            #expect(outcome == .failed(.pasteVerificationUnavailable))
            #expect(textInjection.didRequestAccessIfNeeded)
        }

        @Test func completedCaptureSkipsClipboardWhenCopyAndPasteAreDisabled() async {
            let clipboard = TestClipboardService()
            let textInjection = TestTextInjectionService()
            let coordinator = makeCoordinator(clipboard: clipboard, textInjection: textInjection)

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

        @Test func completedCaptureSkipsEmptyText() async {
            let clipboard = TestClipboardService()
            let textInjection = TestTextInjectionService()
            let coordinator = makeCoordinator(clipboard: clipboard, textInjection: textInjection)

            let outcome = await coordinator.handleCompletedCapture(
                text: " \n\t ",
                targetApplication: nil,
                settings: .init(
                    shouldCopyToClipboard: true,
                    shouldAutoPaste: true,
                    shouldRevealPanelOnCapture: true
                ),
                showPanel: {}
            )

            #expect(outcome == .completed)
            #expect(clipboard.copiedTexts.isEmpty)
            #expect(textInjection.pasteTargets.isEmpty)
        }
    }
#endif
