import Foundation
import Combine
#if os(macOS)
    import StetCore
    import StetVisuals
#endif

/// High-frequency visualization changes are observed only by the capsule.
@MainActor
final class DictationMeteringState: ObservableObject {
    @Published var recordingLevel = 0.0
    #if os(macOS)
        @Published var audioFeatures = MacDictationCapsuleVisualSignals.zero
    #endif
}

@MainActor
final class DictationViewModel: ObservableObject {
    typealias ResultTransformer = @MainActor @Sendable (String) async throws -> String

    private let speechService: any SpeechService
    private let historyService: any DictationHistoryRecording
    private let manualActivationFallbackDelay: Duration
    private var activeTask: Task<Void, Never>?
    private var cancellationTask: Task<Void, Never>?
    private var activationFallbackTask: Task<Void, Never>?
    private var levelTask: Task<Void, Never>?
    #if os(macOS)
        private var audioFeatureTask: Task<Void, Never>?
    #endif

    private var isStartingRecording = false
    private var isActivatingRecordingWindow = false
    @Published private var hasPreparedCapture = false
    private var pendingStopAfterStart = false
    private var pendingActivationAfterStart = false
    private var pendingCaptureStoppedHandler: (@MainActor @Sendable () -> Void)?
    private var resultTransformer: ResultTransformer?
    private(set) var captureSessionID: UInt64 = 0

    @Published private(set) var state: DictationState = .idle
    let metering = DictationMeteringState()
    private(set) var recordingLevel: Double {
        get { metering.recordingLevel }
        set { metering.recordingLevel = newValue }
    }
    #if os(macOS)
        private(set) var audioFeatures: MacDictationCapsuleVisualSignals {
            get { metering.audioFeatures }
            set { metering.audioFeatures = newValue }
        }
    #endif

    init(
        speechService: any SpeechService,
        manualActivationFallbackDelay: Duration = .seconds(1),
        historyService: any DictationHistoryRecording = DictationHistoryService.shared
    ) {
        self.speechService = speechService
        self.manualActivationFallbackDelay = manualActivationFallbackDelay
        self.historyService = historyService
    }

    func send(_ action: DictationAction) {
        DictationRuntimeProbe.shared.markAction("dictationAction.\(actionName(for: action))")

        switch action {
        case .startTapped:
            guard case .idle = state else { return }
            startCapture()

        case .stopTapped:
            guard state.isCaptureInFlight else { return }
            stopCapture()

        case .resetTapped:
            reset()

        case .transcriptionSucceeded(let text):
            state = .result(text)

        case .clipboardPending(let text):
            state = .clipboardPending(text)

        case .transcriptionFailed(let failure):
            state = .error(failure)
        }
    }

    func prewarm() async {
        await speechService.prewarm()
    }

    func startCapture(transform: ResultTransformer? = nil) {
        startCapture(activateWhenReady: true, transform: transform)
    }

    func startCapture(
        activateWhenReady: Bool,
        transform: ResultTransformer? = nil
    ) {
        DictationRuntimeProbe.shared.markCaptureStartRequested()
        DictationRuntimeProbe.shared.markAction("startCapture")

        activeTask?.cancel()
        activationFallbackTask?.cancel()
        levelTask?.cancel()
        #if os(macOS)
            audioFeatureTask?.cancel()
        #endif
        let sessionID = beginCaptureSession()
        isStartingRecording = true
        isActivatingRecordingWindow = false
        hasPreparedCapture = false
        pendingStopAfterStart = false
        pendingActivationAfterStart = false
        pendingCaptureStoppedHandler = nil
        resultTransformer = transform
        recordingLevel = 0
        state = .starting

        let shouldActivateAfterStart = activateWhenReady
        let speechService = self.speechService
        let pendingCancellation = cancellationTask
        activeTask = Task {
            do {
                await pendingCancellation?.value
                try Task.checkCancellation()
                if shouldActivateAfterStart {
                    try await speechService.startRecordingAndActivate()
                } else {
                    try await speechService.startRecording()
                }
                guard isCurrentCaptureSession(sessionID) else { return }

                isStartingRecording = false
                hasPreparedCapture = true
                recordingLevel = 0.08
                startLevelMonitoring()
                #if os(macOS)
                    startAudioFeatureMonitoring()
                #endif

                if pendingStopAfterStart {
                    pendingStopAfterStart = false
                    stopCapture()
                    return
                }

                if shouldActivateAfterStart {
                    pendingActivationAfterStart = false
                    state = .listening
                    DictationRuntimeProbe.shared.markAction("enteredListening")

                    DictationStartupProbe.shared.record(.listeningStateEntered)
                } else {
                    scheduleActivationFallbackIfNeeded()
                }

                guard isCurrentCaptureSession(sessionID) else { return }
                if pendingActivationAfterStart {
                    pendingActivationAfterStart = false
                    try await activateCaptureWindowInline()
                }
            } catch is CancellationError {
                guard isCurrentCaptureSession(sessionID) else { return }
                activationFallbackTask?.cancel()
                activationFallbackTask = nil
                isStartingRecording = false
                isActivatingRecordingWindow = false
                hasPreparedCapture = false
                pendingStopAfterStart = false
                pendingActivationAfterStart = false
                pendingCaptureStoppedHandler = nil
                resultTransformer = nil
                finishLevelMonitoring()
                #if os(macOS)
                    finishAudioFeatureMonitoring()
                #endif

                state = .idle
                DictationRuntimeProbe.shared.markCaptureStartError("cancelled")
                DictationStartupProbe.shared.record(.cancelled)
            } catch {
                guard isCurrentCaptureSession(sessionID) else { return }
                activationFallbackTask?.cancel()
                activationFallbackTask = nil
                isStartingRecording = false
                isActivatingRecordingWindow = false
                hasPreparedCapture = false
                pendingStopAfterStart = false
                pendingActivationAfterStart = false
                pendingCaptureStoppedHandler = nil
                resultTransformer = nil
                finishLevelMonitoring()
                #if os(macOS)
                    finishAudioFeatureMonitoring()
                #endif

                state = .error(.from(error))
                DictationRuntimeProbe.shared.markCaptureStartError(error.localizedDescription)
                DictationStartupProbe.shared.record(.failed, note: error.localizedDescription)
            }
        }
    }

    func activateCaptureWindow() {
        if isStartingRecording {
            pendingActivationAfterStart = true
            return
        }

        guard hasPreparedCapture,
            !isActivatingRecordingWindow,
            state == .starting
        else {
            return
        }

        activationFallbackTask?.cancel()
        activationFallbackTask = nil
        let sessionID = captureSessionID
        activeTask = Task {
            do {
                try await activateCaptureWindowInline()
            } catch is CancellationError {
                guard isCurrentCaptureSession(sessionID) else { return }
                activationFallbackTask?.cancel()
                activationFallbackTask = nil
                isActivatingRecordingWindow = false
                hasPreparedCapture = false
                pendingActivationAfterStart = false
                resultTransformer = nil
                finishLevelMonitoring()
                #if os(macOS)
                    finishAudioFeatureMonitoring()
                #endif

                state = .idle
            } catch {
                guard isCurrentCaptureSession(sessionID) else { return }
                activationFallbackTask?.cancel()
                activationFallbackTask = nil
                isActivatingRecordingWindow = false
                hasPreparedCapture = false
                pendingActivationAfterStart = false
                resultTransformer = nil
                finishLevelMonitoring()
                #if os(macOS)
                    finishAudioFeatureMonitoring()
                #endif

                state = .error(.from(error))
            }
        }
    }

    private func activateCaptureWindowInline() async throws {
        guard hasPreparedCapture,
            !isActivatingRecordingWindow,
            state == .starting
        else {
            return
        }

        activationFallbackTask?.cancel()
        activationFallbackTask = nil
        isActivatingRecordingWindow = true
        let sessionID = captureSessionID

        do {
            try await speechService.activateRecordingWindow()
            guard isCurrentCaptureSession(sessionID) else { return }

            isActivatingRecordingWindow = false
            state = .listening
            DictationRuntimeProbe.shared.markAction("enteredListening")

            DictationStartupProbe.shared.record(.listeningStateEntered)
            guard isCurrentCaptureSession(sessionID) else { return }

            if pendingStopAfterStart {
                pendingStopAfterStart = false
                stopCapture()
            }
        } catch {
            guard isCurrentCaptureSession(sessionID) else { return }
            isActivatingRecordingWindow = false
            throw error
        }
    }

    func stopCapture(onCaptureStopped: (@MainActor @Sendable () -> Void)? = nil) {
        DictationRuntimeProbe.shared.markCaptureStopRequested()
        DictationRuntimeProbe.shared.markAudioStopRequested()

        if let onCaptureStopped {
            pendingCaptureStoppedHandler = onCaptureStopped
        }
        if isStartingRecording || isActivatingRecordingWindow {
            pendingStopAfterStart = true
            return
        }

        activationFallbackTask?.cancel()
        activationFallbackTask = nil
        pendingStopAfterStart = false
        pendingActivationAfterStart = false
        hasPreparedCapture = false
        isActivatingRecordingWindow = false
        finishLevelMonitoring()
        #if os(macOS)
            finishAudioFeatureMonitoring()
        #endif
        state = .processing
        let captureStoppedHandler = pendingCaptureStoppedHandler
        pendingCaptureStoppedHandler = nil
        let sessionID = captureSessionID
        DictationRuntimeProbe.shared.markAction("processingFromStopCapture")

        activeTask = Task {
            do {
                let transcription = try await speechService.stopRecording(
                    onCaptureStopped: {
                        guard let captureStoppedHandler else { return }
                        await MainActor.run {
                            guard self.isCurrentCaptureSession(sessionID) else { return }
                            captureStoppedHandler()
                        }
                    }
                )
                guard isCurrentCaptureSession(sessionID) else { return }
                let finalText: String
                if let resultTransformer {
                    finalText = try await resultTransformer(transcription.text)
                    guard isCurrentCaptureSession(sessionID) else { return }
                } else {
                    finalText = transcription.text
                }
                guard isCurrentCaptureSession(sessionID) else { return }
                // Commit both History stages together after the last suspension.
                historyService.recordRaw(transcription.rawText)
                if resultTransformer != nil || transcription.wasRewritten {
                    historyService.recordLLM(finalText)
                }
                // Persist immediately — every transcription is recorded whether or
                // not the text is ultimately delivered to a target app.
                historyService.commitPending()
                self.resultTransformer = nil
                send(.transcriptionSucceeded(finalText))
            } catch is CancellationError {
                guard isCurrentCaptureSession(sessionID) else { return }
                activationFallbackTask?.cancel()
                activationFallbackTask = nil
                resultTransformer = nil
                hasPreparedCapture = false
                isActivatingRecordingWindow = false
                pendingCaptureStoppedHandler = nil
                finishLevelMonitoring()
                #if os(macOS)
                    finishAudioFeatureMonitoring()
                #endif

                state = .idle
            } catch let error as SpeechServiceError where error == .emptyTranscription {
                guard isCurrentCaptureSession(sessionID) else { return }
                activationFallbackTask?.cancel()
                activationFallbackTask = nil
                resultTransformer = nil
                hasPreparedCapture = false
                isActivatingRecordingWindow = false
                pendingCaptureStoppedHandler = nil
                finishLevelMonitoring()
                #if os(macOS)
                    finishAudioFeatureMonitoring()
                #endif

                state = .idle
                DictationRuntimeProbe.shared.markAction("stopCaptureEmptyTranscription")
            } catch {
                guard isCurrentCaptureSession(sessionID) else { return }
                activationFallbackTask?.cancel()
                activationFallbackTask = nil
                resultTransformer = nil
                hasPreparedCapture = false
                isActivatingRecordingWindow = false
                pendingCaptureStoppedHandler = nil
                finishLevelMonitoring()
                #if os(macOS)
                    finishAudioFeatureMonitoring()
                #endif

                send(.transcriptionFailed(.from(error)))
                DictationRuntimeProbe.shared.markAction("stopCaptureFailed")
            }
        }
    }

    private func reset() {
        DictationRuntimeProbe.shared.markAction("reset")

        invalidateCaptureSession()
        activeTask?.cancel()
        activationFallbackTask?.cancel()
        activationFallbackTask = nil
        finishLevelMonitoring()
        #if os(macOS)
            finishAudioFeatureMonitoring()
        #endif
        isStartingRecording = false
        isActivatingRecordingWindow = false
        hasPreparedCapture = false
        pendingStopAfterStart = false
        pendingActivationAfterStart = false
        pendingCaptureStoppedHandler = nil
        resultTransformer = nil
        let pendingCancellation = cancellationTask
        cancellationTask = Task {
            await pendingCancellation?.value
            await speechService.cancelRecording()
        }
        activeTask = nil
        state = .idle
    }

    private func beginCaptureSession() -> UInt64 {
        captureSessionID += 1
        return captureSessionID
    }

    private func invalidateCaptureSession() {
        captureSessionID += 1
    }

    private func isCurrentCaptureSession(_ sessionID: UInt64) -> Bool {
        !Task.isCancelled && sessionID == captureSessionID
    }

    private func scheduleActivationFallbackIfNeeded() {
        activationFallbackTask?.cancel()
        activationFallbackTask = Task { [weak self] in
            try? await Task.sleep(for: self?.manualActivationFallbackDelay ?? .seconds(1))
            guard let self,
                !Task.isCancelled,
                self.hasPreparedCapture,
                self.state == .starting
            else {
                return
            }

            self.activationFallbackTask = nil
            // Use the same error and cancellation cleanup as explicit activation.
            self.activateCaptureWindow()
        }
    }

    private func startLevelMonitoring() {
        DictationRuntimeProbe.shared.markMeteringStarted()

        guard let streamingService = speechService as? any AudioLevelSource else { return }

        levelTask = Task { @MainActor [weak self] in
            let stream = await streamingService.makeAudioLevelStream()
            for await level in stream {
                guard !Task.isCancelled else { break }
                self?.recordingLevel = level
            }
        }
    }

    private func finishLevelMonitoring() {
        DictationRuntimeProbe.shared.markMeteringStopped()

        levelTask?.cancel()
        levelTask = nil
        recordingLevel = 0
    }

    #if os(macOS)
        private func startAudioFeatureMonitoring() {
            audioFeatureTask?.cancel()
            guard let streamingService = speechService as? any AudioFeatureSource else { return }

            audioFeatureTask = Task { @MainActor [weak self] in
                let stream = await streamingService.makeAudioFeatureStream()
                for await features in stream {
                    guard !Task.isCancelled else { break }
                    self?.audioFeatures = features
                }
            }
        }

        private func finishAudioFeatureMonitoring() {
            audioFeatureTask?.cancel()
            audioFeatureTask = nil
            audioFeatures = .zero
        }
    #endif

    private func actionName(for action: DictationAction) -> String {
        switch action {
        case .startTapped:
            return "startTapped"
        case .stopTapped:
            return "stopTapped"
        case .resetTapped:
            return "resetTapped"
        case .transcriptionSucceeded:
            return "transcriptionSucceeded"
        case .clipboardPending:
            return "clipboardPending"
        case .transcriptionFailed:
            return "transcriptionFailed"
        }
    }
}
