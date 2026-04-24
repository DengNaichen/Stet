#if os(macOS)
    import AppKit
    import Foundation
    import NaturalLanguage

    @MainActor
    final class MacDictationWorkflowController {
        enum PrimaryActionSource {
            case interface
            case hotkey
        }

        typealias CompletionOutcome = MacDictationCaptureCoordinator.CompletionOutcome

        let dictationViewModel: DictationViewModel

        private let captureCoordinator: MacDictationCaptureCoordinator
        private let mediaPlaybackController: any MediaPlaybackControlling
        private let systemAudioMuting: (any SystemAudioMuting)?
        private let settingsStore: DictationSettingsStore
        private let interactionSoundPlayer: any InteractionSoundPlaying
        private let mediaResumeDelay: Duration
        private let startPromptActivationDeadline: Duration

        private weak var lastTargetApplication: NSRunningApplication?
        private(set) var activeRecordingSource: PrimaryActionSource?
        private var mediaResumeTask: Task<Void, Never>?
        private var startActivationTask: Task<Void, Never>?
        private var sessionStartDate: Date?
        private var pendingSessionDuration: TimeInterval?
        private let statsModel: DictationStatsModel?

        init(
            dictationViewModel: DictationViewModel,
            captureCoordinator: MacDictationCaptureCoordinator,
            mediaPlaybackController: any MediaPlaybackControlling,
            systemAudioMuting: (any SystemAudioMuting)? = nil,
            settingsStore: DictationSettingsStore,
            interactionSoundPlayer: any InteractionSoundPlaying,
            statsModel: DictationStatsModel? = nil,
            mediaResumeDelay: Duration = .seconds(1),
            startPromptActivationDeadline: Duration = .milliseconds(350)
        ) {
            self.dictationViewModel = dictationViewModel
            self.captureCoordinator = captureCoordinator
            self.mediaPlaybackController = mediaPlaybackController
            self.systemAudioMuting = systemAudioMuting
            self.settingsStore = settingsStore
            self.interactionSoundPlayer = interactionSoundPlayer
            self.statsModel = statsModel
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
                if dictationViewModel.recordingLevel > 0 {
                    return "Listening..."
                }
                return "Starting microphone..."
            case .listening:
                return "Listening..."
            case .processing:
                return "Processing..."
            case .result:
                return "Transcription complete"
            case .clipboardPending:
                return "Copy to clipboard"
            case .error(let failure):
                return failure.statusText
            }
        }

        var processingStatusText: String {
            let providerName = settingsSnapshot.provider.displayName
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
            activeRecordingSource = source
            sessionStartDate = Date()
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
            if let start = sessionStartDate {
                let duration = Date().timeIntervalSince(start)
                pendingSessionDuration = duration >= 1 ? duration : nil
                sessionStartDate = nil
            }
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
            sessionStartDate = nil
            pendingSessionDuration = nil
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
        }

        func prewarm() async {
            await dictationViewModel.prewarm()
        }

        func handleCompletedResult(
            text: String,
            showTransientPanel: @escaping @MainActor () -> Void
        ) async -> CompletionOutcome {
            Task {
                await DictationRuntimeProbe.shared.markAction("handleCompletedResult")
            }
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                await DictationLatencyProbe.shared.record(.systemWriteSkipped, note: "empty_text")
                pendingSessionDuration = nil
                return .failed(.emptyTranscription)
            }

            if let duration = pendingSessionDuration {
                let wordCount = Self.countWords(in: text)
                statsModel?.record(
                    startedAt: Date().addingTimeInterval(-duration), durationSeconds: duration, wordCount: wordCount)
                pendingSessionDuration = nil
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

        private static func countWords(in text: String) -> Int {
            let tokenizer = NLTokenizer(unit: .word)
            tokenizer.string = text
            var count = 0
            tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { _, _ in
                count += 1
                return true
            }
            return count
        }

        private func matchesListeningState(_ state: DictationState) -> Bool {
            if case .listening = state {
                return true
            }

            return false
        }
    }
#endif
