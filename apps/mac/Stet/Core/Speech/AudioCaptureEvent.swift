import Foundation

enum AudioCaptureEvent: Sendable, Equatable {
    case endpointDetected
}

protocol AudioCaptureEventSource: Sendable {
    func makeAudioCaptureEventStream() async -> AsyncStream<AudioCaptureEvent>
}
