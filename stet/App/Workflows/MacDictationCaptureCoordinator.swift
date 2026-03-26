#if os(macOS)
    import AppKit
    import Foundation

    @MainActor
    final class MacDictationCaptureCoordinator {
        enum CompletionOutcome: Equatable {
            case completed
            case clipboardPending
            case failed(DictationFailure)
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
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                await DictationLatencyProbe.shared.record(.systemWriteSkipped, note: "empty_text")
                return .completed
            }

            let shouldRestoreClipboardAfterSuccessfulPaste =
                settings.shouldAutoPaste && !settings.shouldCopyToClipboard

            if shouldRestoreClipboardAfterSuccessfulPaste {
                pasteboardRestoreCoordinator.prepareForTemporaryOverride(on: pasteboard)
            } else if settings.shouldCopyToClipboard || settings.shouldAutoPaste {
                pasteboardRestoreCoordinator.discardPendingRestore()
            }

            if settings.shouldCopyToClipboard || settings.shouldAutoPaste {
                let clipboardSuccess = clipboardService.copy(
                    text,
                    transient: settings.shouldAutoPaste && !settings.shouldCopyToClipboard
                )
                if !clipboardSuccess {
                    await DictationLatencyProbe.shared.record(
                        .systemWriteFailed, note: "clipboard_write_failed")
                    return .failed(.clipboardWriteFailed)
                }
            }

            if settings.shouldAutoPaste {
                if !textInjectionService.isAvailable {
                    if shouldRestoreClipboardAfterSuccessfulPaste {
                        pasteboardRestoreCoordinator.restoreImmediatelyIfNeeded(on: pasteboard)
                    }

                    if !settings.shouldCopyToClipboard {
                        let fallbackSuccess = clipboardService.copy(text, transient: false)
                        if !fallbackSuccess {
                            await DictationLatencyProbe.shared.record(
                                .systemWriteFailed, note: "clipboard_fallback_failed")
                            return .failed(.clipboardWriteFailed)
                        }
                    }

                    textInjectionService.requestAccessIfNeeded()
                    if settings.shouldRevealPanelOnCapture {
                        showPanel()
                    }

                    await DictationLatencyProbe.shared.record(
                        .systemWriteFailed, note: "auto_paste_permission_missing")
                    return .failed(.autoPastePermissionMissing)
                }

                let pasteOutcome = await textInjectionService.pasteClipboard(into: targetApplication)

                switch pasteOutcome {
                case .verifiedSuccess:
                    if shouldRestoreClipboardAfterSuccessfulPaste {
                        pasteboardRestoreCoordinator.scheduleRestoreIfNeeded(on: pasteboard)
                    }
                    await DictationLatencyProbe.shared.record(.systemWriteCompleted)
                    return .completed

                case .eventPostedVerificationUnavailable, .verificationFailed, .eventPostFailed:
                    if shouldRestoreClipboardAfterSuccessfulPaste {
                        pasteboardRestoreCoordinator.restoreImmediatelyIfNeeded(on: pasteboard)
                    }

                    if !settings.shouldCopyToClipboard {
                        let fallbackSuccess = clipboardService.copy(text, transient: false)
                        if !fallbackSuccess {
                            await DictationLatencyProbe.shared.record(
                                .systemWriteFailed, note: "clipboard_fallback_failed")
                            return .failed(.clipboardWriteFailed)
                        }
                    }

                    let failure: DictationFailure
                    let failureNote: String

                    switch pasteOutcome {
                    case .eventPostedVerificationUnavailable:
                        failure = .pasteVerificationUnavailable
                        failureNote = "paste_verification_unavailable"
                    case .verificationFailed:
                        failure = .pasteVerificationFailed
                        failureNote = "paste_verification_failed"
                    case .eventPostFailed:
                        failure = .pasteVerificationFailed
                        failureNote = "paste_event_post_failed"
                    case .verifiedSuccess:
                        failure = .pasteVerificationFailed
                        failureNote = "unexpected"
                    }

                    if settings.shouldRevealPanelOnCapture {
                        showPanel()
                    }

                    await DictationLatencyProbe.shared.record(
                        .systemWriteFailed, note: failureNote)

                    return .failed(failure)
                }
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

        func copyToClipboard(_ text: String) -> Bool {
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return true
            }
            pasteboardRestoreCoordinator.discardPendingRestore()
            return clipboardService.copy(text, transient: false)
        }
    }
#endif
