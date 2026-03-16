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

    let dictationViewModel: DictationViewModel

    private let captureCoordinator: MacDictationCaptureCoordinator
    private let textInjectionService: any TextInjectionService
    private let mediaPlaybackController: any MediaPlaybackControlling
    private let settingsStore: DictationSettingsStore
    private let interactionSoundPlayer: InteractionSoundPlayer
    private let defaults: UserDefaults

    private weak var lastTargetApplication: NSRunningApplication?
    private(set) var activeRecordingSource: PrimaryActionSource?
    private(set) var activeWorkflow: CaptureWorkflow = .dictation

    init(
        dictationViewModel: DictationViewModel,
        captureCoordinator: MacDictationCaptureCoordinator,
        textInjectionService: any TextInjectionService,
        mediaPlaybackController: any MediaPlaybackControlling,
        settingsStore: DictationSettingsStore,
        interactionSoundPlayer: InteractionSoundPlayer,
        defaults: UserDefaults = .standard
    ) {
        self.dictationViewModel = dictationViewModel
        self.captureCoordinator = captureCoordinator
        self.textInjectionService = textInjectionService
        self.mediaPlaybackController = mediaPlaybackController
        self.settingsStore = settingsStore
        self.interactionSoundPlayer = interactionSoundPlayer
        self.defaults = defaults
    }

    var statusText: String {
        switch dictationViewModel.state {
        case .idle:
            return "Ready"
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
        case .error:
            return "Something went wrong"
        }
    }

    var processingStatusText: String {
        switch activeWorkflow {
        case .translationFromSpeech, .translationFromSelection:
            return "Translating with OpenAI..."
        case .rewriteFromSelection:
            return "Rewriting selected text with OpenAI..."
        case .dictation:
            break
        }

        return settingsSnapshot.isRewriteEnabled
            ? "Transcribing with OpenAI and rewriting..."
            : "Transcribing with OpenAI..."
    }

    func startDictationCapture(
        source: PrimaryActionSource,
        showTransientPanel: @escaping @MainActor () -> Void
    ) {
        refreshTargetApplication()
        activeWorkflow = .dictation
        activeRecordingSource = source
        showTransientPanel()
        dictationViewModel.startCapture()
    }

    func stopActiveCapture() {
        activeRecordingSource = nil
        dictationViewModel.stopCapture()
    }

    func cancelActiveCapture() {
        activeRecordingSource = nil
        dictationViewModel.send(.resetTapped)
    }

    func handleStateTransition(from previousState: DictationState, to newState: DictationState) {
        handleMediaTransition(from: previousState, to: newState)

        if case .listening = newState {
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
    ) async {
        if workflow.isSelectionReplacement {
            await handleSelectedTextReplacementResult(text: text, showTransientPanel: showTransientPanel)
            return
        }

        await captureCoordinator.handleCompletedCapture(
            text: text,
            targetApplication: lastTargetApplication,
            settings: captureSettings,
            showPanel: showTransientPanel
        )
    }

    private func handleSelectedTextReplacementResult(
        text: String,
        showTransientPanel: @escaping @MainActor () -> Void
    ) async {
        let keepResultInClipboard = captureSettings.shouldCopyToClipboard
        let didReplaceSelection = await textInjectionService.replaceSelectedText(
            text,
            into: lastTargetApplication,
            keepResultInClipboard: keepResultInClipboard
        )

        if !didReplaceSelection {
            if !textInjectionService.isAvailable {
                textInjectionService.requestAccessIfNeeded()
            }

            if captureSettings.shouldRevealPanelOnCapture {
                showTransientPanel()
            }
        }
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
            shouldCopyToClipboard: defaults.bool(forKey: MacPreferences.copyToClipboardOnCapture),
            shouldAutoPaste: defaults.bool(forKey: MacPreferences.autoPasteOnCapture),
            shouldRevealPanelOnCapture: defaults.bool(forKey: MacPreferences.revealPanelOnCapture)
        )
    }

    private func handleMediaTransition(from previousState: DictationState, to newState: DictationState) {
        if settingsSnapshot.interactionSoundsEnabled {
            if case .idle = previousState, case .listening = newState {
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

        if isActiveDictationState(previousState),
           shouldResumeMedia(after: newState) {
            mediaPlaybackController.resumePlaybackIfNeeded()
        }
    }

    private func isActiveDictationState(_ state: DictationState) -> Bool {
        switch state {
        case .listening, .processing:
            return true
        case .idle, .result, .error:
            return false
        }
    }

    private func shouldResumeMedia(after state: DictationState) -> Bool {
        switch state {
        case .idle, .result, .error:
            return true
        case .listening, .processing:
            return false
        }
    }

    private func matchesErrorState(_ state: DictationState) -> Bool {
        if case .error = state {
            return true
        }

        return false
    }
}
#endif
