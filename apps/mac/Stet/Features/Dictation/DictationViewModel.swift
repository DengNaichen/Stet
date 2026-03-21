import Foundation
import Combine

@MainActor
final class DictationViewModel: ObservableObject {
    typealias ResultTransformer = @MainActor @Sendable (String) async throws -> String
    typealias ExternalOperation = @MainActor @Sendable () async throws -> String

    private let speechService: any SpeechService
    private var activeTask: Task<Void, Never>?
    private var captureStartupTask: Task<Void, Error>?
    private var levelTask: Task<Void, Never>?

    private var isStartingRecording = false
    private var isActivatingRecordingWindow = false
    private var hasPreparedCapture = false
    private var pendingStopAfterStart = false
    private var pendingActivationAfterStart = false
    private var resultTransformer: ResultTransformer?

    @Published private(set) var state: DictationState = .idle
    @Published private(set) var recordingLevel = 0.0

    init(speechService: any SpeechService) {
        self.speechService = speechService
    }

    func send(_ action: DictationAction) {
        Task {
            await DictationRuntimeProbe.shared.markAction("dictationAction.\(actionName(for: action))")
        }

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
        Task {
            await DictationRuntimeProbe.shared.markCaptureStartRequested()
            await DictationRuntimeProbe.shared.markAction("startCapture")
        }

        activeTask?.cancel()
        captureStartupTask?.cancel()
        levelTask?.cancel()
        isStartingRecording = true
        isActivatingRecordingWindow = false
        hasPreparedCapture = false
        pendingStopAfterStart = false
        pendingActivationAfterStart = false
        resultTransformer = transform
        recordingLevel = 0
        state = .starting

        let shouldActivateAfterStart = activateWhenReady
        let speechService = self.speechService
        let captureStartupTask = Task.detached(priority: .userInitiated) {
            if shouldActivateAfterStart {
                try await speechService.startRecordingAndActivate()
            } else {
                try await speechService.startRecording()
            }
        }
        self.captureStartupTask = captureStartupTask

        activeTask = Task {
            do {
                try await captureStartupTask.value
                self.captureStartupTask = nil
                if Task.isCancelled { return }

                isStartingRecording = false
                hasPreparedCapture = true
                recordingLevel = 0.08
                startLevelMonitoring()

                if shouldActivateAfterStart {
                    pendingActivationAfterStart = false
                    state = .listening
                    Task {
                        await DictationRuntimeProbe.shared.markAction("enteredListening")
                    }
                    await DictationStartupProbe.shared.record(.listeningStateEntered)
                }

                if pendingStopAfterStart {
                    pendingStopAfterStart = false
                    stopCapture()
                    return
                }
            } catch is CancellationError {
                captureStartupTask.cancel()
                self.captureStartupTask = nil
                isStartingRecording = false
                isActivatingRecordingWindow = false
                hasPreparedCapture = false
                pendingStopAfterStart = false
                pendingActivationAfterStart = false
                resultTransformer = nil
                finishLevelMonitoring()

                state = .idle
                Task {
                    await DictationRuntimeProbe.shared.markCaptureStartError("cancelled")
                }
                Task {
                    await DictationStartupProbe.shared.record(.cancelled)
                }
            } catch {
                captureStartupTask.cancel()
                self.captureStartupTask = nil
                isStartingRecording = false
                isActivatingRecordingWindow = false
                hasPreparedCapture = false
                pendingStopAfterStart = false
                pendingActivationAfterStart = false
                resultTransformer = nil
                finishLevelMonitoring()

                state = .error(.from(error))
                Task {
                    await DictationRuntimeProbe.shared.markCaptureStartError(error.localizedDescription)
                }
                Task {
                    await DictationStartupProbe.shared.record(.failed, note: error.localizedDescription)
                }
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
              state == .starting else {
            return
        }

        activeTask = Task {
            do {
                try await activateCaptureWindowInline()
            } catch is CancellationError {
                isActivatingRecordingWindow = false
                hasPreparedCapture = false
                pendingActivationAfterStart = false
                resultTransformer = nil
                finishLevelMonitoring()

                state = .idle
            } catch {
                isActivatingRecordingWindow = false
                hasPreparedCapture = false
                pendingActivationAfterStart = false
                resultTransformer = nil
                finishLevelMonitoring()

                state = .error(.from(error))
            }
        }
    }

    private func activateCaptureWindowInline() async throws {
        guard hasPreparedCapture,
              !isActivatingRecordingWindow,
              state == .starting else {
            return
        }

        isActivatingRecordingWindow = true

        do {
            try await speechService.activateRecordingWindow()
            if Task.isCancelled { return }

            isActivatingRecordingWindow = false
            state = .listening
            Task {
                await DictationRuntimeProbe.shared.markAction("enteredListening")
            }
            await DictationStartupProbe.shared.record(.listeningStateEntered)

            if pendingStopAfterStart {
                pendingStopAfterStart = false
                stopCapture()
            }
        } catch {
            isActivatingRecordingWindow = false
            throw error
        }
    }

    func stopCapture() {
        Task {
            await DictationRuntimeProbe.shared.markCaptureStopRequested()
            await DictationRuntimeProbe.shared.markAudioStopRequested()
        }
        if isStartingRecording || isActivatingRecordingWindow {
            pendingStopAfterStart = true
            return
        }

        pendingStopAfterStart = false
        pendingActivationAfterStart = false
        hasPreparedCapture = false
        isActivatingRecordingWindow = false
        finishLevelMonitoring()
        // finishCaptureEventMonitoring()
        state = .processing
        Task {
            await DictationRuntimeProbe.shared.markAction("processingFromStopCapture")
        }

        activeTask = Task {
            do {
                let text = try await speechService.stopRecording()
                if Task.isCancelled { return }
                let finalText: String
                if let resultTransformer {
                    finalText = try await resultTransformer(text)
                } else {
                    finalText = text
                }
                self.resultTransformer = nil
                send(.transcriptionSucceeded(finalText))
            } catch is CancellationError {
                resultTransformer = nil
                hasPreparedCapture = false
                isActivatingRecordingWindow = false
                finishLevelMonitoring()

                state = .idle
            } catch let error as SpeechServiceError where error == .emptyTranscription {
                resultTransformer = nil
                hasPreparedCapture = false
                isActivatingRecordingWindow = false
                finishLevelMonitoring()

                state = .idle
                Task {
                    await DictationRuntimeProbe.shared.markAction("stopCaptureEmptyTranscription")
                }
            } catch {
                resultTransformer = nil
                hasPreparedCapture = false
                isActivatingRecordingWindow = false
                finishLevelMonitoring()

                send(.transcriptionFailed(.from(error)))
                Task {
                    await DictationRuntimeProbe.shared.markAction("stopCaptureFailed")
                }
            }
        }
    }

    func runProcessingOperation(_ operation: @escaping ExternalOperation) {
        activeTask?.cancel()
        captureStartupTask?.cancel()
        captureStartupTask = nil
        finishLevelMonitoring()
        // finishCaptureEventMonitoring()
        isStartingRecording = false
        isActivatingRecordingWindow = false
        hasPreparedCapture = false
        pendingStopAfterStart = false
        pendingActivationAfterStart = false
        resultTransformer = nil
        state = .processing

        activeTask = Task {
            do {
                let text = try await operation()
                if Task.isCancelled { return }
                send(.transcriptionSucceeded(text))
            } catch is CancellationError {
                finishLevelMonitoring()

                state = .idle
            } catch {
                finishLevelMonitoring()

                send(.transcriptionFailed(.from(error)))
            }

        }
    }

    private func reset() {
        Task {
            await DictationRuntimeProbe.shared.markAction("reset")
        }
        activeTask?.cancel()
        captureStartupTask?.cancel()
        captureStartupTask = nil
        finishLevelMonitoring()
        isStartingRecording = false
        isActivatingRecordingWindow = false
        hasPreparedCapture = false
        pendingStopAfterStart = false
        pendingActivationAfterStart = false
        resultTransformer = nil
        activeTask = Task {
            await speechService.cancelRecording()
        }
        state = .idle
    }

    private func startLevelMonitoring() {
        Task {
            await DictationRuntimeProbe.shared.markMeteringStarted()
        }
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
        Task {
            await DictationRuntimeProbe.shared.markMeteringStopped()
        }
        levelTask?.cancel()
        levelTask = nil
        recordingLevel = 0
    }

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
