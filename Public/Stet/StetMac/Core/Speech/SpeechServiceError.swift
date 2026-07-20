import Foundation

enum SpeechServiceError: LocalizedError, Equatable {
    case alreadyRecording
    case notRecording
    case microphonePermissionDenied
    case unsupportedLocale
    case unsupportedAudioFormat
    case failedToStart
    case emptyTranscription

    var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            return "A dictation session is already in progress."
        case .notRecording:
            return "There is no active dictation session to stop."
        case .microphonePermissionDenied:
            return "Microphone access is required to start dictation."
        case .unsupportedLocale:
            return "The current language is not available for on-device dictation."
        case .unsupportedAudioFormat:
            return "This device could not provide a compatible audio format for transcription."
        case .failedToStart:
            return "The dictation engine could not be started."
        case .emptyTranscription:
            return "No speech was captured. Try speaking a little closer to the microphone."
        }
    }
}
