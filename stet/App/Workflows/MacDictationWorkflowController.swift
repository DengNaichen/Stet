#if os(macOS)
    import AppKit
    import Foundation

    @MainActor
    final class MacDictationWorkflowController {
        enum PrimaryActionSource {
            case interface
            case hotkey
        }

        enum CaptureWorkflow: Equatable {
            case dictation
            case rewriteFromSelection(sourceText: String)

            var isSelectionReplacement: Bool {
                switch self {
                case .rewriteFromSelection:
                    return true
                case .dictation:
                    return false
                }
            }
        }

        typealias CompletionOutcome = MacDictationCaptureCoordinator.CompletionOutcome

        let dictationViewModel: DictationViewModel

        private let captureCoordinator: MacDictationCaptureCoordinator
        private let textInjectionService: any TextInjectionService
        private let mediaPlaybackController: any MediaPlaybackControlling
        private let systemAudioMuting: (any SystemAudioMuting)?
        private let settingsStore: DictationSettingsStore
        private let interactionSoundPlayer: any InteractionSoundPlaying
        private let mediaResumeDelay: Duration
        private let startPromptActivationDeadline: Duration

        private weak var lastTargetApplication: NSRunningApplication?
        private(set) var activeRecordingSource: PrimaryActionSource?
        private(set) var activeWorkflow: CaptureWorkflow = .dictation
        private var mediaResumeTask: Task<Void, Never>?
        private var startActivationTask: Task<Void, Never>?

        init(
            dictationViewModel: DictationViewModel,
            captureCoordinator: MacDictationCaptureCoordinator,
            textInjectionService: any TextInjectionService,
            mediaPlaybackController: any MediaPlaybackControlling,
            systemAudioMuting: (any SystemAudioMuting)? = nil,
            settingsStore: DictationSettingsStore,
            interactionSoundPlayer: any InteractionSoundPlaying,
            mediaResumeDelay: Duration = .seconds(1),
            startPromptActivationDeadline: Duration = .milliseconds(350)
        ) {
            self.dictationViewModel = dictationViewModel
            self.captureCoordinator = captureCoordinator
            self.textInjectionService = textInjectionService
            self.mediaPlaybackController = mediaPlaybackController
            self.systemAudioMuting = systemAudioMuting
            self.settingsStore = settingsStore
            self.interactionSoundPlayer = interactionSoundPlayer
            self.mediaResumeDelay = mediaResumeDelay
            self.startPromptActivationDeadline = startPromptActivationDeadline
        }

        deinit {
            mediaResumeTask?.cancel()
            startActivationTask?.cancel()
            let systemAudioMuting = self.systemAudioMuting
            Task { @MainActor in
                systemAudioMuting?.restoreMuteIfNeeded()
            }
        }

        var statusText: String {
            switch dictationViewModel.state {
            case .idle:
                return "Ready"
            case .starting:
                switch activeWorkflow {
                case .rewriteFromSelection:
                    return "Preparing rewrite capture..."
                case .dictation:
                    return "Starting microphone..."
                }
            case .listening:
                switch activeWorkflow {
                case .rewriteFromSelection:
                    return "Listening for rewrite instructions..."
                case .dictation:
                    return "Listening..."
                }
            case .processing:
                switch activeWorkflow {
                case .rewriteFromSelection:
                    return "Rewriting selected text..."
                case .dictation:
                    return "Processing..."
                }
            case .result:
                switch activeWorkflow {
                case .rewriteFromSelection:
                    return "Rewrite complete"
                case .dictation:
                    return "Transcription complete"
                }
            case .clipboardPending:
                switch activeWorkflow {
                case .rewriteFromSelection:
                    return "Copy rewritten text"
                case .dictation:
                    return "Copy to clipboard"
                }
            case .error(let failure):
                return failure.statusText
            }
        }

        var processingStatusText: String {
            let providerName = settingsSnapshot.provider.displayName

            switch activeWorkflow {
            case .rewriteFromSelection:
                return "Rewriting selected text with \(providerName)..."
            case .dictation:
                break
            }

            return "Transcribing with \(providerName) and rewriting..."
        }

        func startDictationCapture(
            source: PrimaryActionSource,
            allowCurrentAppTarget: Bool = false,
            showTransientPanel: @escaping @MainActor () -> Void
        ) {
            Task {
                await DictationRuntimeProbe.shared.markAction("startDictationCapture")
            }
            refreshTargetApplication(allowingCurrentAppTarget: allowCurrentAppTarget)
            activeWorkflow = .dictation
            activeRecordingSource = source
            mediaResumeTask?.cancel()
            mediaResumeTask = nil

            let settings = settingsSnapshot
            if settings.shouldPauseMediaDuringDictation {
                mediaPlaybackController.pausePlaybackIfNeeded()
            }

            let shouldDelayActivationForPrompt = settings.interactionSoundsEnabled
            dictationViewModel.startCapture(activateWhenReady: !shouldDelayActivationForPrompt)
            showTransientPanel()

            startActivationTask?.cancel()
            guard shouldDelayActivationForPrompt else {
                startActivationTask = nil
                return
            }

            startActivationTask = Task { @MainActor [weak self] in
                guard let self else { return }
                defer { startActivationTask = nil }

                await awaitStartPromptBeforeActivation(preset: settings.interactionSoundPreset)

                guard !Task.isCancelled else { return }
                dictationViewModel.activateCaptureWindow()
            }
        }

        func stopActiveCapture() {
            activeRecordingSource = nil
            startActivationTask?.cancel()
            startActivationTask = nil
            Task {
                await DictationRuntimeProbe.shared.markAction("stopActiveCapture")
            }
            let settings = settingsSnapshot

            dictationViewModel.stopCapture(onCaptureStopped: { [weak self] in
                guard settings.interactionSoundsEnabled else { return }
                self?.interactionSoundPlayer.playFinish(preset: settings.interactionSoundPreset)
            })
        }

        func cancelActiveCapture() {
            activeRecordingSource = nil
            startActivationTask?.cancel()
            startActivationTask = nil
            Task {
                await DictationRuntimeProbe.shared.markAction("cancelActiveCapture")
            }
            dictationViewModel.send(.resetTapped)
        }

        func handleStateTransition(from previousState: DictationState, to newState: DictationState) {
            Task {
                await DictationRuntimeProbe.shared.markAction("workflowHandleStateTransition")
            }
            handleMediaTransition(from: previousState, to: newState)

            if newState.isCaptureInFlight {
                return
            }

            activeRecordingSource = nil
        }

        func resetWorkflowIfNeeded() {
            guard activeRecordingSource == nil else { return }
            activeWorkflow = .dictation
        }

        func prewarm() async {
            await dictationViewModel.prewarm()
        }

        func handleCompletedResult(
            text: String,
            workflow: CaptureWorkflow,
            showTransientPanel: @escaping @MainActor () -> Void
        ) async -> CompletionOutcome {
            Task {
                await DictationRuntimeProbe.shared.markAction("handleCompletedResult workflow=\(workflow)")
            }
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                await DictationLatencyProbe.shared.record(.systemWriteSkipped, note: "empty_text")
                return .failed(.emptyTranscription)
            }
            if workflow.isSelectionReplacement {
                return await handleSelectedTextReplacementResult(text: text, showTransientPanel: showTransientPanel)
            }

            return await captureCoordinator.handleCompletedCapture(
                text: text,
                targetApplication: lastTargetApplication,
                settings: captureSettings,
                showPanel: showTransientPanel
            )
        }

        func copyPendingResultToClipboard(_ text: String) -> Bool {
            Task {
                await DictationRuntimeProbe.shared.markAction("copyPendingResultToClipboard")
            }
            return captureCoordinator.copyToClipboard(text)
        }

        private func handleSelectedTextReplacementResult(
            text: String,
            showTransientPanel: @escaping @MainActor () -> Void
        ) async -> CompletionOutcome {
            let keepResultInClipboard = captureSettings.shouldCopyToClipboard
            let replacementOutcome = await textInjectionService.replaceSelectedText(
                text,
                into: lastTargetApplication,
                keepResultInClipboard: keepResultInClipboard
            )

            if replacementOutcome == .replaced {
                await DictationLatencyProbe.shared.record(.systemWriteCompleted)
                return .completed
            } else {
                await DictationLatencyProbe.shared.record(.systemWriteFailed, note: "replace_selected_text_failed")
            }

            switch replacementOutcome {
            case .replaced:
                return .completed

            case .clipboardWriteFailed:
                return .failed(.clipboardWriteFailed)

            case .injectionFailed(let injectionOutcome):
                if injectionOutcome == .eventPostFailed && !textInjectionService.isAvailable {
                    textInjectionService.requestAccessIfNeeded()

                    if !keepResultInClipboard {
                        let clipboardSuccess = captureCoordinator.copyToClipboard(text)
                        if !clipboardSuccess {
                            return .failed(.clipboardWriteFailed)
                        }
                    }

                    if captureSettings.shouldRevealPanelOnCapture {
                        showTransientPanel()
                    }

                    return .failed(.autoPastePermissionMissing)
                }

                if !keepResultInClipboard {
                    let clipboardSuccess = captureCoordinator.copyToClipboard(text)
                    if !clipboardSuccess {
                        return .failed(.clipboardWriteFailed)
                    }
                }

                if captureSettings.shouldRevealPanelOnCapture {
                    showTransientPanel()
                }

                switch injectionOutcome {
                case .eventPostedVerificationUnavailable:
                    return .failed(.pasteVerificationUnavailable)
                case .verificationFailed, .eventPostFailed:
                    return .failed(.pasteVerificationFailed)
                case .verifiedSuccess:
                    return .completed
                }
            }
        }

        private func refreshTargetApplication(allowingCurrentAppTarget: Bool) {
            let frontmostApplication = NSWorkspace.shared.frontmostApplication
            guard let frontmostApplication,
                allowingCurrentAppTarget || frontmostApplication.bundleIdentifier != Bundle.main.bundleIdentifier
            else {
                return
            }

            lastTargetApplication = frontmostApplication
        }

        private var settingsSnapshot: DictationSettingsSnapshot {
            settingsStore.loadSnapshot()
        }

        private var captureSettings: MacDictationCaptureCoordinator.CaptureSettings {
            MacDictationCaptureCoordinator.CaptureSettings(
                shouldCopyToClipboard: false,
                shouldAutoPaste: true,
                shouldRevealPanelOnCapture: false
            )
        }

        private func awaitStartPromptBeforeActivation(preset: InteractionSoundPreset) async {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { [interactionSoundPlayer] in
                    await interactionSoundPlayer.playStartPrompt(preset: preset)
                }
                group.addTask {
                    try? await Task.sleep(for: self.startPromptActivationDeadline)
                }

                await group.next()
                group.cancelAll()
            }
        }

        private func handleMediaTransition(from previousState: DictationState, to newState: DictationState) {
            if newState.isCaptureInFlight, !previousState.isCaptureInFlight {
                mediaResumeTask?.cancel()
                mediaResumeTask = nil
            }

            // Keep the heavy system mute out of launch/startup work.
            // External playback is paused earlier; the tap is only activated once
            // capture is actually live.
            if settingsSnapshot.shouldPauseMediaDuringDictation,
                matchesListeningState(newState)
            {
                _ = systemAudioMuting?.activateMuteIfNeeded()
            }

            if previousState.isCaptureInFlight,
                !newState.isCaptureInFlight
            {
                startActivationTask?.cancel()
                startActivationTask = nil
                scheduleMediaResumeIfNeeded()
            }
        }

        private func scheduleMediaResumeIfNeeded() {
            let delay = mediaResumeDelay

            mediaResumeTask?.cancel()

            mediaResumeTask = Task { @MainActor [weak self] in
                guard let self else { return }

                // Let macOS release capture-side routing before restoring external audio.
                if delay > .zero {
                    try? await Task.sleep(for: delay)
                }

                guard !Task.isCancelled,
                    !matchesListeningState(dictationViewModel.state)
                else {
                    return
                }

                systemAudioMuting?.restoreMuteIfNeeded()
                mediaPlaybackController.resumePlaybackIfNeeded()
                mediaResumeTask = nil
            }
        }

        private func matchesListeningState(_ state: DictationState) -> Bool {
            if case .listening = state {
                return true
            }

            return false
        }
    }
#endif
