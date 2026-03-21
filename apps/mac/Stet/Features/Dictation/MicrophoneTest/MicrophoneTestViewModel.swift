import Foundation
import Combine

/// ViewModel for microphone testing functionality
@MainActor
final class MicrophoneTestViewModel: ObservableObject {
    // MARK: - Published Properties
    
    @Published private(set) var isRecording = false
    @Published private(set) var isPlaying = false
    @Published private(set) var audioLevel: Double = 0.0
    @Published private(set) var hasRecording = false
    
    // MARK: - Private Properties
    
    private let microphoneTestService: MicrophoneTestService
    private var recordingURL: URL?
    private var audioLevelTask: Task<Void, Never>?
    
    // MARK: - Initialization
    
    init(microphoneTestService: MicrophoneTestService) {
        self.microphoneTestService = microphoneTestService
    }
    
    // MARK: - Recording Methods
    
    func startRecording() async {
        guard !isRecording else { return }

        do {
            try await microphoneTestService.startRecording()
            isRecording = true
            hasRecording = false
            isPlaying = false
            recordingURL = nil
            audioLevel = 0.0
            startAudioLevelObservation()
        } catch {
            print("[MicrophoneTestViewModel] Failed to start recording: \(error.localizedDescription)")
            isRecording = false
            audioLevel = 0.0
            stopAudioLevelObservation()
        }
    }
    
    func stopRecording() async {
        guard isRecording else { return }

        stopAudioLevelObservation()

        do {
            let url = try await microphoneTestService.stopRecording()
            recordingURL = url
            isRecording = false
            hasRecording = true
            audioLevel = 0.0
        } catch {
            print("[MicrophoneTestViewModel] Failed to stop recording: \(error.localizedDescription)")
            isRecording = false
            audioLevel = 0.0
        }
    }
    
    // MARK: - Playback Methods
    
    func playRecording() async {
        guard let url = recordingURL, !isPlaying else { return }

        do {
            isPlaying = true
            defer { isPlaying = false }
            try await microphoneTestService.playRecording(at: url)
        } catch {
            print("[MicrophoneTestViewModel] Failed to play recording: \(error.localizedDescription)")
            isPlaying = false
        }
    }
    
    func stopPlayback() {
        microphoneTestService.stopPlayback()
        isPlaying = false
    }
    
    // MARK: - Private Methods
    
    private func startAudioLevelObservation() {
        audioLevelTask?.cancel()
        audioLevelTask = Task { @MainActor [weak self, microphoneTestService] in
            let stream = await microphoneTestService.makeAudioLevelStream()
            for await level in stream {
                guard !Task.isCancelled else { break }
                guard let self else { break }
                self.audioLevel = level
            }
        }
    }
    
    private func stopAudioLevelObservation() {
        audioLevelTask?.cancel()
        audioLevelTask = nil
    }
}
