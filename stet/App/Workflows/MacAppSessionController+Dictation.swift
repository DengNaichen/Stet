#if os(macOS)
    import Combine
    import Foundation

    extension MacAppSessionController {
        func performPrimaryAction() {
            performPrimaryAction(source: .interface)
        }
    }

    extension MacAppSessionController {
        func performPrimaryAction(source: PrimaryActionSource) {
            Task {
                await DictationRuntimeProbe.shared.markAction("performPrimaryAction:\(source)")
            }

            if requiresOnboarding && !onboardingStepState.allowsAudioCapture {
                presentRequiredPermissionsGateIfNeeded()
                return
            }

            switch dictationState {
            case .idle, .result, .error:
                if source == .interface {
                    Task {
                        await DictationStartupProbe.shared.begin(trigger: .interface)
                    }
                }
                requestDictationCaptureStart(from: source)
            case .clipboardPending(let text):
                commitPendingCopy(text)
            case .starting, .listening:
                requestDictationCaptureStopIfNeeded()
            case .processing:
                break
            }
        }

        func handleHotkeyPressed() {
            let action = hotkeyInteraction.handleKeyDown(
                for: dictationState,
                now: ProcessInfo.processInfo.systemUptime
            )
            if action == .startCapture {
                Task {
                    await DictationStartupProbe.shared.begin(trigger: .hotkey)
                }
            }
            performHotkeyAction(action)
        }

        func handleHotkeyReleased() {
            let action = hotkeyInteraction.handleKeyUp(
                for: dictationState,
                now: ProcessInfo.processInfo.systemUptime
            )
            performHotkeyAction(action)
        }

        func showTransientPanel() {
            guard let presentationModel else { return }
            shellPresentationController.showTransientPanel(appModel: presentationModel)
            Task {
                await DictationRuntimeProbe.shared.markPanelShown()
            }
            Task {
                await DictationStartupProbe.shared.record(.panelShown)
            }
        }

        func bindState() {
            workflowController.dictationViewModel.$state
                .dropFirst()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] state in
                    self?.handleDictationStateChange(state)
                }
                .store(in: &cancellables)
        }

        func handleDictationStateChange(_ state: DictationState) {
            handleStateTransitionObservation(for: state)
            handlePanelAndIdleLifecycle(for: state)
            handleResultLifecycle(for: state)
        }

        func handleStateTransitionObservation(for state: DictationState) {
            let previousState = previousDictationState
            previousDictationState = state
            hotkeyInteraction.sync(with: state)
            Task {
                await DictationRuntimeProbe.shared.markStateTransition(from: previousState, to: state)
                if state == .idle, previousState != .idle {
                    await DictationRuntimeProbe.shared.endRun(
                        reason: "state_idle", details: "from=\(stateLabel(previousState))")
                }
            }
            cancelPendingStateTasks()
            updateOnboardingProgress(previousState: previousState, state: state)
            workflowController.handleStateTransition(from: previousState, to: state)
        }

        func handlePanelAndIdleLifecycle(for state: DictationState) {
            switch state {
            case .starting, .listening, .error, .clipboardPending:
                showTransientPanelIfNeeded()
            case .idle:
                guard workflowController.activeRecordingSource == nil else { return }
                workflowController.resetWorkflowIfNeeded()
                scheduleTransientPanelHideIfNeeded()
            case .processing, .result:
                break
            }
        }

        func handleResultLifecycle(for state: DictationState) {
            guard case .result(let text) = state else { return }

            completionHandlingTask = Task { @MainActor [weak self] in
                guard let self else { return }
                let outcome = await workflowController.handleCompletedResult(
                    text: text,
                    showTransientPanel: showTransientPanel
                )
                let recoveredTextPreserved =
                    if case .failed(let failure) = outcome {
                        failure.preservesRecoveredTextInClipboard
                    } else {
                        false
                    }
                Task {
                    await DictationRuntimeProbe.shared.markResultHandled(
                        clipboardPending: outcome == .clipboardPending || recoveredTextPreserved,
                        textLength: text.count
                    )
                }

                guard !Task.isCancelled else {
                    AppLogger.info(
                        "OutputTrace stage=session_result_mapping_skipped reason=task_cancelled outcome=\(completionOutcomeLabel(outcome))",
                        category: .perfTrace
                    )
                    return
                }
                guard case .result = dictationState else {
                    AppLogger.info(
                        "OutputTrace stage=session_result_mapping_skipped reason=state_changed currentState=\(stateLabel(dictationState)) outcome=\(completionOutcomeLabel(outcome))",
                        category: .perfTrace
                    )
                    return
                }

                AppLogger.info(
                    "OutputTrace stage=session_result_mapping_apply outcome=\(completionOutcomeLabel(outcome)) recoveredTextPreserved=\(recoveredTextPreserved) panelVisible=\(isPanelVisible)",
                    category: .perfTrace
                )

                switch outcome {
                case .completed:
                    hidePanel()
                    workflowController.dictationViewModel.send(.resetTapped)
                case .clipboardPending:
                    if !isPanelVisible {
                        showTransientPanel()
                    }
                    workflowController.dictationViewModel.send(.clipboardPending(text))
                case .failed(let failure):
                    if failure.preservesRecoveredTextInClipboard {
                        if !isPanelVisible {
                            showTransientPanel()
                        }
                        workflowController.dictationViewModel.send(.clipboardPending(text))
                    } else {
                        workflowController.dictationViewModel.send(.transcriptionFailed(failure))
                    }
                }
            }
        }

        func cancelPendingStateTasks() {
            completionHandlingTask?.cancel()
            completionHandlingTask = nil
            shellPresentationController.cancelScheduledPanelHide()
        }

        func scheduleTransientPanelHideIfNeeded() {
            shellPresentationController.scheduleTransientPanelHideIfNeeded { [weak self] in
                self?.dictationState ?? .idle
            }
        }

        func showTransientPanelIfNeeded() {
            guard !isPanelVisible else { return }
            showTransientPanel()
        }

        func registerHotkeys() {
            hotkeyRegistrar.clearDictationHandlers()
            hotkeyRegistrar.registerDictationKeyDown { [weak self] in
                self?.handleHotkeyPressed()
            }
            hotkeyRegistrar.registerDictationKeyUp { [weak self] in
                self?.handleHotkeyReleased()
            }
        }

        func performHotkeyAction(_ action: MacDictationHotkeyInteraction.Action) {
            switch action {
            case .none:
                break
            case .startCapture:
                requestDictationCaptureStart(from: .hotkey)
            case .stopCapture:
                requestDictationCaptureStopIfNeeded()
            }
        }

        func requestDictationCaptureStart(from source: PrimaryActionSource) {
            #if APP_STORE
                if TrialStore.shared.isExpired && !PurchaseStore.shared.isUnlocked {
                    showPaywall?()
                    return
                }
            #endif

            if requiresOnboarding && !onboardingStepState.allowsAudioCapture {
                Task {
                    await DictationStartupProbe.shared.record(.failed, note: "onboarding_gate")
                }
                presentRequiredPermissionsGateIfNeeded()
                return
            }

            guard hasRequiredPermissions else {
                Task {
                    await DictationStartupProbe.shared.record(.failed, note: "permissions_gate")
                }

                presentRequiredPermissionsGateIfNeeded()
                return
            }

            Task {
                await DictationStartupProbe.shared.record(.permissionsVerified)
                await DictationRuntimeProbe.shared.endRun(reason: "start_requested_after_previous")
                await DictationRuntimeProbe.shared.markCaptureStartRequested()
                await DictationRuntimeProbe.shared.beginRun(
                    trigger: "captureStart",
                    source: "MacAppSessionController",
                    panelVisible: isPanelVisible
                )
            }

            switch dictationState {
            case .idle:
                startDictationCapture(from: source)
            case .result, .error:
                workflowController.dictationViewModel.send(.resetTapped)
                startDictationCapture(from: source)
            case .clipboardPending, .starting, .listening, .processing:
                break
            }
        }

        func startDictationCapture(from source: PrimaryActionSource) {
            workflowController.startDictationCapture(
                source: source,
                allowCurrentAppTarget: requiresOnboarding && onboardingStepState == .firstSuccess,
                showTransientPanel: { [weak self] in
                    self?.showTransientPanel()
                }
            )
            Task {
                await DictationRuntimeProbe.shared.markAction("startDictationCapture")
            }
        }

        func requestDictationCaptureStopIfNeeded() {
            Task {
                await DictationRuntimeProbe.shared.markCaptureStopRequested()
            }
            guard dictationState.isCaptureInFlight else { return }
            workflowController.stopActiveCapture()
        }

        func commitPendingCopy(_ text: String) {
            let copied = workflowController.copyPendingResultToClipboard(text)
            guard copied else {
                return
            }

            hidePanel()
            workflowController.dictationViewModel.send(.resetTapped)
            Task {
                await DictationRuntimeProbe.shared.markPendingCopyCommitted()
            }
        }

        func stateLabel(_ state: DictationState) -> String {
            switch state {
            case .idle:
                return "idle"
            case .starting:
                return "starting"
            case .listening:
                return "listening"
            case .processing:
                return "processing"
            case .result:
                return "result"
            case .clipboardPending:
                return "clipboardPending"
            case .error:
                return "error"
            }
        }

        func completionOutcomeLabel(
            _ outcome: MacDictationCaptureCoordinator.CompletionOutcome
        ) -> String {
            switch outcome {
            case .completed:
                return "completed"
            case .clipboardPending:
                return "clipboardPending"
            case .failed(let failure):
                return "failed:\(failureLabel(failure))"
            }
        }

        func failureLabel(_ failure: DictationFailure) -> String {
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
    }
#endif
