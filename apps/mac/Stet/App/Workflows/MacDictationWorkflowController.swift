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
        case translationFromSpeech
        case translationFromSelection(sourceText: String)
        case rewriteFromSelection(sourceText: String)

        var isSelectionReplacement: Bool {
            switch self {
            case .translationFromSelection, .rewriteFromSelection:
                return true
            case .dictation, .translationFromSpeech:
                return false
            }
        }
    }

    typealias CompletionOutcome = MacDictationCaptureCoordinator.CompletionOutcome

    let dictationViewModel: DictationViewModel

    private let captureCoordinator: MacDictationCaptureCoordinator
    private let textInjectionService: any TextInjectionService
    private let mediaPlaybackController: any MediaPlaybackControlling
    private let settingsStore: DictationSettingsStore
    private let interactionSoundPlayer: InteractionSoundPlayer
    private let mediaResumeDelay: Duration

    private weak var lastTargetApplication: NSRunningApplication?
    private(set) var activeRecordingSource: PrimaryActionSource?
    private(set) var activeWorkflow: CaptureWorkflow = .dictation
    private var mediaResumeTask: Task<Void, Never>?

    init(
        dictationViewModel: DictationViewModel,
        captureCoordinator: MacDictationCaptureCoordinator,
        textInjectionService: any TextInjectionService,
        mediaPlaybackController: any MediaPlaybackControlling,
        settingsStore: DictationSettingsStore,
        interactionSoundPlayer: InteractionSoundPlayer,
        mediaResumeDelay: Duration = .seconds(1)
    ) {
        self.dictationViewModel = dictationViewModel
        self.captureCoordinator = captureCoordinator
        self.textInjectionService = textInjectionService
        self.mediaPlaybackController = mediaPlaybackController
        self.settingsStore = settingsStore
        self.interactionSoundPlayer = interactionSoundPlayer
        self.mediaResumeDelay = mediaResumeDelay
    }

    deinit {
        mediaResumeTask?.cancel()
    }

    var statusText: String {
        switch dictationViewModel.state {
        case .idle:
            return "Ready"
        case .starting:
            switch activeWorkflow {
            case .rewriteFromSelection:
                return "Preparing rewrite capture..."
            case .translationFromSpeech:
                return "Preparing translation capture..."
            case .dictation, .translationFromSelection:
                return "Starting microphone..."
            }
        case .listening:
            switch activeWorkflow {
            case .rewriteFromSelection:
                return "Listening for rewrite instructions..."
            case .translationFromSpeech:
                return "Listening for translation..."
            case .dictation, .translationFromSelection:
                return "Listening..."
            }
        case .processing:
            switch activeWorkflow {
            case .translationFromSpeech, .translationFromSelection:
                return "Translating..."
            case .rewriteFromSelection:
                return "Rewriting selected text..."
            case .dictation:
                return "Processing..."
            }
        case .result:
            switch activeWorkflow {
            case .translationFromSpeech, .translationFromSelection:
                return "Translation complete"
            case .rewriteFromSelection:
                return "Rewrite complete"
            case .dictation:
                return "Transcription complete"
            }
        case .clipboardPending:
            switch activeWorkflow {
            case .translationFromSpeech, .translationFromSelection:
                return "Copy translation"
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
        case .translationFromSpeech, .translationFromSelection:
            return "Translating with \(providerName)..."
        case .rewriteFromSelection:
            return "Rewriting selected text with \(providerName)..."
        case .dictation:
            break
        }

        return settingsSnapshot.isRewriteEnabled
            ? "Transcribing with \(providerName) and rewriting..."
            : "Transcribing with \(providerName)..."
    }

    func startDictationCapture(
        source: PrimaryActionSource,
        showTransientPanel: @escaping @MainActor () -> Void
    ) {
        Task {
            await DictationRuntimeProbe.shared.markAction("startDictationCapture")
        }
        refreshTargetApplication()
        activeWorkflow = .dictation
        activeRecordingSource = source
        showTransientPanel()
        dictationViewModel.startCapture()
    }

    func stopActiveCapture() {
        activeRecordingSource = nil
        Task {
            await DictationRuntimeProbe.shared.markAction("stopActiveCapture")
        }
        dictationViewModel.stopCapture()
    }

    func cancelActiveCapture() {
        activeRecordingSource = nil
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

    func handleCompletedResult(
        text: String,
        workflow: CaptureWorkflow,
        showTransientPanel: @escaping @MainActor () -> Void
    ) async -> CompletionOutcome {
        Task {
            await DictationRuntimeProbe.shared.markAction("handleCompletedResult workflow=\(workflow)")
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

    func copyPendingResultToClipboard(_ text: String) {
        Task {
            await DictationRuntimeProbe.shared.markAction("copyPendingResultToClipboard")
        }
        captureCoordinator.copyToClipboard(text)
    }

    private func handleSelectedTextReplacementResult(
        text: String,
        showTransientPanel: @escaping @MainActor () -> Void
    ) async -> CompletionOutcome {
        let keepResultInClipboard = captureSettings.shouldCopyToClipboard
        let didReplaceSelection = await textInjectionService.replaceSelectedText(
            text,
            into: lastTargetApplication,
            keepResultInClipboard: keepResultInClipboard
        )

        if didReplaceSelection {
            await DictationLatencyProbe.shared.record(.systemWriteCompleted)
            return .completed
        } else {
            await DictationLatencyProbe.shared.record(.systemWriteFailed, note: "replace_selected_text_failed")
        }

        if !didReplaceSelection {
            if !textInjectionService.isAvailable {
                textInjectionService.requestAccessIfNeeded()
            }

            if captureSettings.shouldRevealPanelOnCapture {
                showTransientPanel()
            }
        }

        return keepResultInClipboard ? .completed : .clipboardPending
    }

    private func refreshTargetApplication() {
        let frontmostApplication = NSWorkspace.shared.frontmostApplication
        guard let frontmostApplication,
              frontmostApplication.bundleIdentifier != Bundle.main.bundleIdentifier else {
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

    private func handleMediaTransition(from previousState: DictationState, to newState: DictationState) {
        if newState.isCaptureInFlight, !previousState.isCaptureInFlight {
            mediaResumeTask?.cancel()
            mediaResumeTask = nil
        }

        if settingsSnapshot.interactionSoundsEnabled {
            if newState == .listening, !matchesListeningState(previousState) {
                interactionSoundPlayer.playStart(preset: settingsSnapshot.interactionSoundPreset)
            } else if isActiveDictationState(previousState),
                      shouldResumeMedia(after: newState),
                      !matchesErrorState(newState) {
                interactionSoundPlayer.playFinish(preset: settingsSnapshot.interactionSoundPreset)
            }
        }

        if case .listening = newState {
            if case .listening = previousState {
                return
            }

            if settingsSnapshot.shouldPauseMediaDuringDictation {
                mediaPlaybackController.pausePlaybackIfNeeded()
            }
            return
        }

        if case .listening = previousState,
           !matchesListeningState(newState) {
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
                  !matchesListeningState(dictationViewModel.state) else {
                return
            }

            mediaPlaybackController.resumePlaybackIfNeeded()
            mediaResumeTask = nil
        }
    }

    private func isActiveDictationState(_ state: DictationState) -> Bool {
        switch state {
        case .listening, .processing:
            return true
        case .idle, .starting, .result, .clipboardPending, .error:
            return false
        }
    }

    private func shouldResumeMedia(after state: DictationState) -> Bool {
        switch state {
        case .idle, .starting, .result, .clipboardPending, .error:
            return true
        case .listening, .processing:
            return false
        }
    }

    private func matchesListeningState(_ state: DictationState) -> Bool {
        if case .listening = state {
            return true
        }

        return false
    }

    private func matchesErrorState(_ state: DictationState) -> Bool {
        if case .error = state {
            return true
        }

        return false
    }
}
#endif
