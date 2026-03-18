import Foundation

enum DictationState: Equatable {
    case idle
    case listening
    case processing
    case result(String)
    case clipboardPending(String)
    case error(String)

    var statusText: String {
        switch self {
        case .idle:
            return "Ready"
        case .listening:
            return "Listening..."
        case .processing:
            return "Processing..."
        case .result:
            return "Transcription complete"
        case .clipboardPending:
            return "Copy to clipboard"
        case .error:
            return "Something went wrong"
        }
    }
}
