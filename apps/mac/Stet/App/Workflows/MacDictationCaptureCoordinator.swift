#if os(macOS)
    import AppKit
    import Foundation

    @MainActor
    final class MacDictationCaptureCoordinator {
        enum CompletionOutcome: Equatable {
            case completed
            case clipboardPending
        }

        struct CaptureSettings {
            let shouldCopyToClipboard: Bool
            let shouldAutoPaste: Bool
            let shouldRevealPanelOnCapture: Bool
        }

        private let clipboardService: any ClipboardService
        private let textInjectionService: any TextInjectionService
        private let pasteboard: NSPasteboard
        private let pasteboardRestoreCoordinator: PasteboardRestoreCoordinator

        init(
            clipboardService: any ClipboardService,
            textInjectionService: any TextInjectionService,
            pasteboard: NSPasteboard = .general,
            pasteboardRestoreCoordinator: PasteboardRestoreCoordinator? = nil
        ) {
            self.clipboardService = clipboardService
            self.textInjectionService = textInjectionService
            self.pasteboard = pasteboard
            self.pasteboardRestoreCoordinator =
                pasteboardRestoreCoordinator ?? PasteboardRestoreCoordinator()
        }

        func handleCompletedCapture(
            text: String,
            targetApplication: NSRunningApplication?,
            settings: CaptureSettings,
            showPanel: @escaping @MainActor () -> Void
        ) async -> CompletionOutcome {
            let shouldRestoreClipboardAfterSuccessfulPaste =
                settings.shouldAutoPaste && !settings.shouldCopyToClipboard

            if shouldRestoreClipboardAfterSuccessfulPaste {
                pasteboardRestoreCoordinator.prepareForTemporaryOverride(on: pasteboard)
            } else if settings.shouldCopyToClipboard || settings.shouldAutoPaste {
                pasteboardRestoreCoordinator.discardPendingRestore()
            }

            if settings.shouldCopyToClipboard || settings.shouldAutoPaste {
                clipboardService.copy(
                    text,
                    transient: settings.shouldAutoPaste && !settings.shouldCopyToClipboard
                )
            }

            if settings.shouldAutoPaste {
                let didPaste = await textInjectionService.pasteClipboard(into: targetApplication)

                if didPaste {
                    if shouldRestoreClipboardAfterSuccessfulPaste {
                        pasteboardRestoreCoordinator.scheduleRestoreIfNeeded(on: pasteboard)
                    }
                    await DictationLatencyProbe.shared.record(.systemWriteCompleted)
                    return .completed
                } else {
                    if shouldRestoreClipboardAfterSuccessfulPaste {
                        pasteboardRestoreCoordinator.restoreImmediatelyIfNeeded(on: pasteboard)
                    }
                    await DictationLatencyProbe.shared.record(
                        .systemWriteFailed, note: "paste_failed")
                }

                if !didPaste && !textInjectionService.isAvailable {
                    textInjectionService.requestAccessIfNeeded()
                }

                if settings.shouldRevealPanelOnCapture && !didPaste {
                    showPanel()
                }

                return settings.shouldCopyToClipboard ? .completed : .clipboardPending
            } else if settings.shouldRevealPanelOnCapture {
                await DictationLatencyProbe.shared.record(
                    .systemWriteSkipped, note: "auto_paste_disabled")
                showPanel()
            } else {
                await DictationLatencyProbe.shared.record(
                    .systemWriteSkipped, note: "auto_paste_disabled")
            }

            return settings.shouldCopyToClipboard ? .completed : .clipboardPending
        }

        func copyToClipboard(_ text: String) {
            pasteboardRestoreCoordinator.discardPendingRestore()
            clipboardService.copy(text, transient: false)
        }
    }
#endif
