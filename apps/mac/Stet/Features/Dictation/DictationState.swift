import Foundation

enum DictationState: Equatable {
    case idle
    case starting
    case listening
    case processing
    case result(String)
    case clipboardPending(String)
    case error(DictationFailure)

    var statusText: String {
        switch self {
        case .idle:
            return "Ready"
        case .starting:
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

    var isCaptureInFlight: Bool {
        switch self {
        case .starting, .listening:
            return true
        case .idle, .processing, .result, .clipboardPending, .error:
            return false
        }
    }
}
