import Foundation

public enum SenseVoiceError: LocalizedError {
    case modelDirectoryUnavailable
    case modelMissing(expectedURL: URL?)
    case runtimeUnavailable
    case initializationFailed
    case audioPreparationFailed
    case transcriptionFailed

    public var errorDescription: String? {
        switch self {
        case .modelDirectoryUnavailable:
            return "Could not resolve the application support directory for SenseVoice models."
        case .modelMissing(let url):
            if let path = url?.path {
                return "SenseVoice model files are missing at: \(path)"
            } else {
                return "SenseVoice model files are missing."
            }
        case .runtimeUnavailable:
            return "The SenseVoice runtime could not be initialized."
        case .initializationFailed:
            return "Failed to initialize the SenseVoice recognizer."
        case .audioPreparationFailed:
            return "Failed to process audio for SenseVoice transcription."
        case .transcriptionFailed:
            return "An error occurred during the SenseVoice transcription process."
        }
    }
}

public enum SenseVoiceModelStatus {
    case ready(localURL: URL)
    case missing(expectedURL: URL?)
    case runtimeUnavailable
}
