import Foundation

enum DictationState: Equatable {
    case idle
    case listening
    case processing
    case result(String)
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
        case .error:
            return "Something went wrong"
        }
    }
}




