import Combine
import Foundation
import UIKit

@MainActor
final class SenseVoiceViewModel: ObservableObject {
    enum State: Equatable {
        case loading
        case idle
        case starting
        case recording
        case processing
        case rewriting
        case failed(String)
    }

    @Published private(set) var state: State = .loading
    @Published private(set) var transcript = ""
    @Published private(set) var partialStatus = "Loading..."
    @Published private(set) var completedSessionId: String?
    @Published private(set) var recordingLevel: Double = 0

    private let coordinator: any DictationSessionCoordinating
    private let liveActivityManager: any MicrophoneLiveActivityManaging
    private let volumeTransport: any DictationVolumeTransporting
    private var eventsListener: Task<Void, Never>?
    private var volumeSampler: AnyCancellable?
    private let impactGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let notificationGenerator = UINotificationFeedbackGenerator()

    init(
        coordinator: any DictationSessionCoordinating,
        liveActivityManager: (any MicrophoneLiveActivityManaging)? = nil,
        volumeTransport: any DictationVolumeTransporting = SharedDictationManager.shared
    ) {
        self.coordinator = coordinator
        self.liveActivityManager = liveActivityManager ?? NoOpMicrophoneLiveActivityManager()
        self.volumeTransport = volumeTransport
    }

    var isRecording: Bool {
        switch state {
        case .starting, .recording:
            true
        default:
            false
        }
    }

    var canToggleRecording: Bool {
        switch state {
        case .idle, .starting, .recording:
            true
        default:
            false
        }
    }

    func start() {
        guard eventsListener == nil else { return }

        let events = coordinator.events
        eventsListener = Task { @MainActor [weak self] in
            for await event in events {
                guard !Task.isCancelled else { break }
                await self?.handle(event)
            }
        }
        coordinator.start()
    }

    func ensureMicAlive() {
        coordinator.recoverAudioSession()
    }

    func toggleRecording() {
        guard canToggleRecording else { return }
        impactGenerator.impactOccurred()

        if isRecording {
            coordinator.stopRecording(sessionId: nil)
        } else {
            coordinator.startRecording(sessionId: UUID().uuidString)
        }
    }

    func clearTranscript() {
        transcript = ""
    }

    func synchronizeExternalRequest() {
        coordinator.synchronizeKeyboardCommands()
    }

    private func handle(_ event: DictationCoordinatorEvent) async {
        switch event {
        case .loading:
            stopVolumeSampling(resetLevel: true)
            state = .loading
            partialStatus = "Preparing speech recognition..."

        case .ready:
            stopVolumeSampling(resetLevel: true)
            state = .idle
            partialStatus = "Ready. Hold mic on keyboard to dictate."
            await liveActivityManager.ensureActive()

        case .starting:
            stopVolumeSampling(resetLevel: true)
            state = .starting
            partialStatus = "Starting microphone..."

        case .recording:
            state = .recording
            partialStatus = "Recording..."
            startVolumeSampling()

        case .transcribing:
            stopVolumeSampling(resetLevel: false)
            state = .processing
            partialStatus = "Decoding..."

        case .rewriting:
            stopVolumeSampling(resetLevel: false)
            state = .rewriting
            partialStatus = "Rewriting..."

        case .partialTranscript(_, let text):
            transcript = text

        case .completed(let sessionId, let text, _):
            stopVolumeSampling(resetLevel: true)
            transcript = text
            state = .idle
            completedSessionId = sessionId
            partialStatus = text.isEmpty ? "Empty result." : "Finished."
            if !text.isEmpty {
                notificationGenerator.notificationOccurred(.success)
            }

        case .failed:
            stopVolumeSampling(resetLevel: true)
            let userFacingMessage = "Dictation isn't available right now. Please try again."
            state = .failed(userFacingMessage)
            partialStatus = userFacingMessage
            await liveActivityManager.endAll()
        }
    }

    private func startVolumeSampling() {
        guard volumeSampler == nil else { return }
        sampleVolume()
        volumeSampler = Timer.publish(every: 0.06, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.sampleVolume()
            }
    }

    private func stopVolumeSampling(resetLevel: Bool) {
        volumeSampler?.cancel()
        volumeSampler = nil
        if resetLevel {
            recordingLevel = 0
        }
    }

    private func sampleVolume() {
        let level = Double(volumeTransport.readVolume())
        recordingLevel = level.isFinite ? min(max(level, 0), 1) : 0
    }
}
