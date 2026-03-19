import Foundation
import Combine

@MainActor
final class DictationViewModel: ObservableObject {
    typealias ResultTransformer = @MainActor @Sendable (String) async throws -> String
    typealias ExternalOperation = @MainActor @Sendable () async throws -> String

    private let speechService: any SpeechService
    private var activeTask: Task<Void, Never>?
    private var levelTask: Task<Void, Never>?
    private var isStartingRecording = false
    private var pendingStopAfterStart = false
    private var resultTransformer: ResultTransformer?

    @Published private(set) var state: DictationState = .idle
    @Published private(set) var recordingLevel = 0.0

    init(speechService: any SpeechService) {
        self.speechService = speechService
    }

    func send(_ action: DictationAction) {
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

    func startCapture(transform: ResultTransformer? = nil) {
        activeTask?.cancel()
        levelTask?.cancel()
        isStartingRecording = true
        pendingStopAfterStart = false
        resultTransformer = transform
        recordingLevel = 0
        state = .starting

        activeTask = Task {
            do {
                try await speechService.startRecording()
                if Task.isCancelled { return }

                isStartingRecording = false
                recordingLevel = 0.08
                startLevelMonitoring()
                state = .listening
                Task {
                    await DictationStartupProbe.shared.record(.listeningStateEntered)
                }

                if pendingStopAfterStart {
                    pendingStopAfterStart = false
                    stopCapture()
                }
            } catch is CancellationError {
                isStartingRecording = false
                pendingStopAfterStart = false
                resultTransformer = nil
                finishLevelMonitoring()
                state = .idle
                Task {
                    await DictationStartupProbe.shared.record(.cancelled)
                }
            } catch {
                isStartingRecording = false
                pendingStopAfterStart = false
                resultTransformer = nil
                finishLevelMonitoring()
                state = .error(.from(error))
                Task {
                    await DictationStartupProbe.shared.record(.failed, note: error.localizedDescription)
                }
            }
        }
    }

    func stopCapture() {
        if isStartingRecording {
            pendingStopAfterStart = true
            return
        }

        pendingStopAfterStart = false
        finishLevelMonitoring()
        state = .processing

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
                finishLevelMonitoring()
                state = .idle
            } catch let error as SpeechServiceError where error == .emptyTranscription {
                resultTransformer = nil
                finishLevelMonitoring()
                state = .idle
            } catch {
                resultTransformer = nil
                finishLevelMonitoring()
                send(.transcriptionFailed(.from(error)))
            }
        }
    }

    func runProcessingOperation(_ operation: @escaping ExternalOperation) {
        activeTask?.cancel()
        finishLevelMonitoring()
        isStartingRecording = false
        pendingStopAfterStart = false
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
        activeTask?.cancel()
        finishLevelMonitoring()
        isStartingRecording = false
        pendingStopAfterStart = false
        resultTransformer = nil
        activeTask = Task {
            await speechService.cancelRecording()
        }
        state = .idle
    }

    private func startLevelMonitoring() {
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
        levelTask?.cancel()
        levelTask = nil
        recordingLevel = 0
    }
}
