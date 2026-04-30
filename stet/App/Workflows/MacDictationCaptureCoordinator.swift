#if os(macOS)
    import AppKit
    import Foundation

    @MainActor
    final class MacDictationCaptureCoordinator {
        private nonisolated static let likelyTextInputRecoveryWindow: Duration = .seconds(2)

        private enum TargetAppOutputProfile: Equatable {
            case optimisticVerificationBlind(recoveryWindow: Duration)
        }

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
        private let frontmostBundleIdentifierProvider: @MainActor () -> String?

        init(
            clipboardService: any ClipboardService,
            textInjectionService: any TextInjectionService,
            pasteboard: NSPasteboard = .general,
            pasteboardRestoreCoordinator: PasteboardRestoreCoordinator? = nil,
            frontmostBundleIdentifierProvider: @escaping @MainActor () -> String? = {
                NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            }
        ) {
            self.clipboardService = clipboardService
            self.textInjectionService = textInjectionService
            self.pasteboard = pasteboard
            self.pasteboardRestoreCoordinator =
                pasteboardRestoreCoordinator ?? PasteboardRestoreCoordinator()
            self.frontmostBundleIdentifierProvider = frontmostBundleIdentifierProvider
        }

        func handleCompletedCapture(
            text: String,
            targetApplication: NSRunningApplication?,
            settings: CaptureSettings,
            showPanel: @escaping @MainActor () -> Void
        ) async -> CompletionOutcome {
            let traceID = makeOutputTraceID()
            emitOutputTrace(
                traceID,
                stage: "begin",
                details:
                    "textLength=\(text.count) target=\(applicationSummary(targetApplication)) shouldCopyToClipboard=\(settings.shouldCopyToClipboard) shouldAutoPaste=\(settings.shouldAutoPaste) shouldRevealPanel=\(settings.shouldRevealPanelOnCapture)"
            )

            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                emitOutputTrace(traceID, stage: "completion", details: "outcome=completed reason=empty_text")
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

            emitOutputTrace(
                traceID,
                stage: "clipboard_strategy",
                details:
                    "shouldRestoreAfterSuccessfulPaste=\(shouldRestoreClipboardAfterSuccessfulPaste) pasteboardChangeCount=\(pasteboard.changeCount)"
            )

            if settings.shouldCopyToClipboard || settings.shouldAutoPaste {
                let isTransientCopy = settings.shouldAutoPaste && !settings.shouldCopyToClipboard
                let clipboardSuccess = clipboardService.copy(
                    text,
                    transient: isTransientCopy
                )
                emitOutputTrace(
                    traceID,
                    stage: "initial_clipboard_copy",
                    details:
                        "success=\(clipboardSuccess) transient=\(isTransientCopy) pasteboardChangeCount=\(pasteboard.changeCount)"
                )
                if !clipboardSuccess {
                    emitOutputTrace(
                        traceID,
                        stage: "completion",
                        details: "outcome=failed failure=clipboardWriteFailed"
                    )
                    await DictationLatencyProbe.shared.record(
                        .systemWriteFailed, note: "clipboard_write_failed")
                    AnalyticsService.track(
                        "output_failed",
                        parameters: ["failure": "\(DictationFailure.clipboardWriteFailed.classification)"])
                    return .failed(.clipboardWriteFailed)
                }
            }

            if settings.shouldAutoPaste {
                if !textInjectionService.isAvailable {
                    let accessState = textInjectionService.accessState
                    emitOutputTrace(
                        traceID,
                        stage: "auto_paste_unavailable",
                        details:
                            "accessibility=\(accessState.hasAccessibilityAccess) postEvent=\(accessState.hasPostEventAccess)"
                    )
                    if shouldRestoreClipboardAfterSuccessfulPaste {
                        pasteboardRestoreCoordinator.restoreImmediatelyIfNeeded(on: pasteboard)
                    }

                    if !settings.shouldCopyToClipboard {
                        let fallbackSuccess = clipboardService.copy(text, transient: false)
                        emitOutputTrace(
                            traceID,
                            stage: "fallback_clipboard_copy",
                            details:
                                "success=\(fallbackSuccess) transient=false pasteboardChangeCount=\(pasteboard.changeCount)"
                        )
                        if !fallbackSuccess {
                            emitOutputTrace(
                                traceID,
                                stage: "completion",
                                details: "outcome=failed failure=clipboardWriteFailed"
                            )
                            await DictationLatencyProbe.shared.record(
                                .systemWriteFailed, note: "clipboard_fallback_failed")
                            AnalyticsService.track(
                                "output_failed",
                                parameters: ["failure": "\(DictationFailure.clipboardWriteFailed.classification)"])
                            return .failed(.clipboardWriteFailed)
                        }
                    }

                    textInjectionService.requestAccessIfNeeded()
                    if settings.shouldRevealPanelOnCapture {
                        showPanel()
                    }

                    await DictationLatencyProbe.shared.record(
                        .systemWriteFailed, note: "auto_paste_permission_missing")
                    emitOutputTrace(
                        traceID,
                        stage: "completion",
                        details: "outcome=failed failure=autoPastePermissionMissing"
                    )
                    AnalyticsService.track(
                        "output_failed",
                        parameters: ["failure": "\(DictationFailure.autoPastePermissionMissing.classification)"])
                    return .failed(.autoPastePermissionMissing)
                }

                let pasteOutcome = await textInjectionService.pasteClipboard(into: targetApplication)
                let targetAppProfile = resolveTargetAppOutputProfile(targetApplication: targetApplication)
                emitOutputTrace(
                    traceID,
                    stage: "text_injection_outcome",
                    details:
                        "outcome=\(textInjectionOutcomeLabel(pasteOutcome)) profile=\(targetAppProfileLabel(targetAppProfile))"
                )

                let optimisticRecoveryWindow =
                    recoveryWindow(
                        for: pasteOutcome,
                        targetAppProfile: targetAppProfile
                    )

                if let optimisticRecoveryWindow {
                    if shouldRestoreClipboardAfterSuccessfulPaste {
                        pasteboardRestoreCoordinator.scheduleRestoreIfNeeded(
                            on: pasteboard,
                            delayOverride: optimisticRecoveryWindow
                        )
                    }

                    await DictationLatencyProbe.shared.record(
                        .systemWriteCompleted,
                        note: "optimistic_verification_blind"
                    )
                    emitOutputTrace(
                        traceID,
                        stage: "completion",
                        details:
                            "outcome=completed reason=optimistic_verification_blind profile=\(targetAppProfileLabel(targetAppProfile))"
                    )
                    AnalyticsService.track("output_success", parameters: ["method": "auto_paste"])
                    return .completed
                }

                switch pasteOutcome {
                case .verifiedSuccess:
                    if shouldRestoreClipboardAfterSuccessfulPaste {
                        pasteboardRestoreCoordinator.scheduleRestoreIfNeeded(on: pasteboard)
                    }
                    await DictationLatencyProbe.shared.record(.systemWriteCompleted)
                    emitOutputTrace(traceID, stage: "completion", details: "outcome=completed")
                    AnalyticsService.track("output_success", parameters: ["method": "auto_paste"])
                    return .completed

                case .eventPostedVerificationUnavailableInTextInput,
                    .eventPostedVerificationUnavailable,
                    .verificationFailed,
                    .eventPostFailed:
                    if shouldRestoreClipboardAfterSuccessfulPaste {
                        pasteboardRestoreCoordinator.restoreImmediatelyIfNeeded(on: pasteboard)
                    }

                    if !settings.shouldCopyToClipboard {
                        let fallbackSuccess = clipboardService.copy(text, transient: false)
                        emitOutputTrace(
                            traceID,
                            stage: "fallback_clipboard_copy",
                            details:
                                "success=\(fallbackSuccess) transient=false pasteboardChangeCount=\(pasteboard.changeCount)"
                        )
                        if !fallbackSuccess {
                            emitOutputTrace(
                                traceID,
                                stage: "completion",
                                details: "outcome=failed failure=clipboardWriteFailed"
                            )
                            await DictationLatencyProbe.shared.record(
                                .systemWriteFailed, note: "clipboard_fallback_failed")
                            AnalyticsService.track(
                                "output_failed",
                                parameters: ["failure": "\(DictationFailure.clipboardWriteFailed.classification)"])
                            return .failed(.clipboardWriteFailed)
                        }
                    }

                    let failure: DictationFailure
                    let failureNote: String

                    switch pasteOutcome {
                    case .eventPostedVerificationUnavailableInTextInput:
                        failure = .pasteVerificationUnavailable
                        failureNote = "paste_verification_unavailable_likely_text_input"
                    case .eventPostedVerificationUnavailable:
                        textInjectionService.requestAccessIfNeeded()
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

                    emitOutputTrace(
                        traceID,
                        stage: "completion",
                        details: "outcome=failed failure=\(failureLabel(failure))"
                    )
                    AnalyticsService.track("output_failed", parameters: ["failure": "\(failure.classification)"])
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

            let outcome: CompletionOutcome = settings.shouldCopyToClipboard ? .completed : .clipboardPending
            emitOutputTrace(
                traceID,
                stage: "completion",
                details: "outcome=\(completionOutcomeLabel(outcome))"
            )
            if outcome == .completed {
                AnalyticsService.track("output_success", parameters: ["method": "clipboard"])
            } else {
                AnalyticsService.track("output_clipboard_pending")
            }
            return outcome
        }

        func copyToClipboard(_ text: String) -> Bool {
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return true
            }
            pasteboardRestoreCoordinator.discardPendingRestore()
            return clipboardService.copy(text, transient: false)
        }

        private func makeOutputTraceID() -> String {
            String(UUID().uuidString.prefix(8))
        }

        private func emitOutputTrace(_ traceID: String, stage: String, details: String? = nil) {
            let detailsSuffix = details.map { " \($0)" } ?? ""
            AppLogger.info(
                "OutputTrace id=\(traceID) stage=\(stage)\(detailsSuffix)",
                category: .perfTrace
            )
        }

        private func applicationSummary(_ application: NSRunningApplication?) -> String {
            guard let application else { return "nil" }
            let bundleIdentifier = application.bundleIdentifier ?? "unknown"
            return "\(bundleIdentifier)(pid=\(application.processIdentifier))"
        }

        private func textInjectionOutcomeLabel(_ outcome: TextInjectionOutcome) -> String {
            switch outcome {
            case .verifiedSuccess:
                return "verifiedSuccess"
            case .eventPostedVerificationUnavailableInTextInput:
                return "eventPostedVerificationUnavailableInTextInput"
            case .eventPostedVerificationUnavailable:
                return "eventPostedVerificationUnavailable"
            case .verificationFailed:
                return "verificationFailed"
            case .eventPostFailed:
                return "eventPostFailed"
            }
        }

        private func completionOutcomeLabel(_ outcome: CompletionOutcome) -> String {
            switch outcome {
            case .completed:
                return "completed"
            case .clipboardPending:
                return "clipboardPending"
            case .failed(let failure):
                return "failed:\(failureLabel(failure))"
            }
        }

        private func failureLabel(_ failure: DictationFailure) -> String {
            switch failure {
            case .clipboardWriteFailed:
                return "clipboardWriteFailed"
            case .autoPastePermissionMissing:
                return "autoPastePermissionMissing"
            case .pasteVerificationUnavailable:
                return "pasteVerificationUnavailable"
            case .pasteVerificationFailed:
                return "pasteVerificationFailed"
            default:
                return "other"
            }
        }

        private func resolveTargetAppOutputProfile(targetApplication: NSRunningApplication?)
            -> TargetAppOutputProfile?
        {
            let bundleIdentifier =
                targetApplication?.bundleIdentifier
                ?? frontmostBundleIdentifierProvider()
            return outputProfile(for: bundleIdentifier)
        }

        private func outputProfile(for bundleIdentifier: String?) -> TargetAppOutputProfile? {
            switch bundleIdentifier?.lowercased() {
            case "com.microsoft.vscode",
                "com.microsoft.vscodeinsiders",
                "com.hnc.discord",
                "notion.id",
                "com.google.chrome",
                "com.anthropic.claude",
                "com.linear",
                "com.tinyspeck.slackmacgap",
                "com.openai.codex",
                "com.google.antigravity",
                "dev.zed.app",
                "dev.zed.zed":
                return .optimisticVerificationBlind(recoveryWindow: .seconds(10))
            default:
                return nil
            }
        }

        private func shouldTreatAsOptimisticCompletion(_ outcome: TextInjectionOutcome) -> Bool {
            switch outcome {
            case .eventPostedVerificationUnavailableInTextInput,
                .eventPostedVerificationUnavailable,
                .verificationFailed:
                return true
            case .verifiedSuccess,
                .eventPostFailed:
                return false
            }
        }

        private func recoveryWindow(
            for outcome: TextInjectionOutcome,
            targetAppProfile: TargetAppOutputProfile?
        ) -> Duration? {
            if case .eventPostedVerificationUnavailableInTextInput = outcome {
                return Self.likelyTextInputRecoveryWindow
            }

            guard case let .optimisticVerificationBlind(recoveryWindow)? = targetAppProfile,
                shouldTreatAsOptimisticCompletion(outcome)
            else {
                return nil
            }

            return recoveryWindow
        }

        private func targetAppProfileLabel(_ profile: TargetAppOutputProfile?) -> String {
            switch profile {
            case .optimisticVerificationBlind:
                return "optimisticVerificationBlind"
            case nil:
                return "none"
            }
        }
    }
#endif
