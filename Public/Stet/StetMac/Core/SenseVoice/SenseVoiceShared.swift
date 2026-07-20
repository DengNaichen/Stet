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
            #if os(macOS)
                return
                    "Could not resolve the application support directory for SenseVoice models. Please check your system permissions."
            #else
                return "Internal storage error. Please reinstall the application."
            #endif
        case .modelMissing(let url):
            #if os(macOS)
                if let path = url?.path {
                    return "SenseVoice model files are missing at: \(path). Please update the path in Settings."
                } else {
                    return "SenseVoice model files are missing. Please download or select them in Settings."
                }
            #else
                return "SenseVoice model components are missing. Please reinstall the application."
            #endif
        case .runtimeUnavailable:
            #if os(macOS)
                return "The SenseVoice runtime could not be initialized. This might be a build configuration issue."
            #else
                return "This device is not compatible with SenseVoice transcription."
            #endif
        case .initializationFailed:
            return "Failed to initialize the SenseVoice recognizer. Please try again."
        case .audioPreparationFailed:
            return "Failed to process audio for SenseVoice transcription. Ensure microphone access is granted."
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
