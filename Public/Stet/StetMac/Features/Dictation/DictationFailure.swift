import Foundation
import StetAI
import StetCore

enum DictationFailure: LocalizedError, Equatable, Sendable {
    enum Classification: Equatable, Sendable {
        case permissions
        case configuration
        case authentication
        case network
        case noSpeech
        case output
        case service
        case state
        case unknown
    }

    case microphonePermissionDenied
    case unsupportedLocale
    case unsupportedAudioFormat
    case failedToStart
    case emptyTranscription
    case alreadyRecording
    case notRecording
    case missingProviderConfiguration(requirements: [ProviderConfigurationRequirement])
    case missingAPIKey(provider: DictationProvider)
    case invalidBaseURL(provider: DictationProvider)
    case invalidResponse(provider: DictationProvider)
    case providerAPI(provider: DictationProvider, statusCode: Int?, message: String)
    case unsupportedProviderCombination(transcriptionProvider: DictationProvider, rewriteProvider: DictationProvider)
    case localWhisperModelMissing(expectedPath: String)
    case localWhisperRuntimeUnavailable
    case network(code: URLError.Code, message: String)
    case clipboardWriteFailed
    case autoPastePermissionMissing
    case pasteVerificationUnavailable
    case pasteVerificationFailed
    case unknown(message: String)

    var classification: Classification {
        switch self {
        case .microphonePermissionDenied:
            return .permissions
        case .unsupportedLocale,
            .unsupportedAudioFormat,
            .failedToStart,
            .invalidResponse,
            .localWhisperRuntimeUnavailable:
            return .service
        case .emptyTranscription:
            return .noSpeech
        case .alreadyRecording, .notRecording:
            return .state
        case .clipboardWriteFailed, .pasteVerificationUnavailable, .pasteVerificationFailed:
            return .output
        case .autoPastePermissionMissing:
            return .permissions
        case .missingProviderConfiguration,
            .missingAPIKey,
            .invalidBaseURL,
            .unsupportedProviderCombination,
            .localWhisperModelMissing:
            return .configuration
        case .providerAPI(_, let statusCode, _):
            switch statusCode {
            case 401, 403:
                return .configuration
            case 408:
                return .network
            default:
                return .service
            }

        case .network:
            return .network
        case .unknown:
            return .unknown
        }
    }

    var statusText: String {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone access required"
        case .unsupportedLocale:
            return "Language unavailable"
        case .unsupportedAudioFormat:
            return "Audio format unavailable"
        case .failedToStart:
            return "Couldn't start dictation"
        case .emptyTranscription:
            return "No speech detected"
        case .alreadyRecording, .notRecording:
            return "Dictation state mismatch"
        case .missingProviderConfiguration:
            return "Provider configuration required"
        case .missingAPIKey(let provider):
            return "\(provider.displayName) API key required"
        case .invalidBaseURL(let provider):
            return "\(provider.displayName) configuration invalid"
        case .invalidResponse(let provider):
            return "\(provider.displayName) returned invalid data"
        case .providerAPI(let provider, _, _):
            return "\(provider.displayName) request failed"
        case .unsupportedProviderCombination:
            return "Unsupported provider pair"

        case .localWhisperModelMissing:
            return "Local Whisper model required"
        case .localWhisperRuntimeUnavailable:
            return "Local Whisper unavailable"
        case .network:
            return "Network problem"
        case .clipboardWriteFailed:
            return "Clipboard write failed"
        case .autoPastePermissionMissing:
            return "Input control permission required"
        case .pasteVerificationUnavailable, .pasteVerificationFailed:
            return "Text copied to clipboard"
        case .unknown:
            return "Something went wrong"
        }
    }

    var message: String {
        switch self {
        case .microphonePermissionDenied:
            return SpeechServiceError.microphonePermissionDenied.localizedDescription
        case .unsupportedLocale:
            return SpeechServiceError.unsupportedLocale.localizedDescription
        case .unsupportedAudioFormat:
            return SpeechServiceError.unsupportedAudioFormat.localizedDescription
        case .failedToStart:
            return SpeechServiceError.failedToStart.localizedDescription
        case .emptyTranscription:
            return SpeechServiceError.emptyTranscription.localizedDescription
        case .alreadyRecording:
            return SpeechServiceError.alreadyRecording.localizedDescription
        case .notRecording:
            return SpeechServiceError.notRecording.localizedDescription
        case .missingProviderConfiguration(let requirements):
            return ProviderConfigurationError.missingRequirements(requirements).localizedDescription
        case .missingAPIKey(let provider):
            return OpenAIError.missingAPIKey(provider: provider).localizedDescription
        case .invalidBaseURL(let provider):
            return OpenAIError.invalidBaseURL(provider: provider).localizedDescription
        case .invalidResponse(let provider):
            return OpenAIError.invalidResponse(provider: provider).localizedDescription
        case .providerAPI(let provider, let statusCode, let message):
            return OpenAIError.api(provider: provider, statusCode: statusCode, message: message).localizedDescription
        case .unsupportedProviderCombination(let transcriptionProvider, let rewriteProvider):
            return
                "\(transcriptionProvider.displayName) transcription with \(rewriteProvider.displayName) rewrite is unsupported."

        case .localWhisperModelMissing(let expectedPath):
            return "Local Whisper model not found. Place the model at \(expectedPath)."
        case .localWhisperRuntimeUnavailable:
            return LocalWhisperError.runtimeUnavailable.localizedDescription
        case .network(_, let message):
            return message
        case .clipboardWriteFailed:
            return "Failed to write text to clipboard. Please try again or paste manually."
        case .autoPastePermissionMissing:
            return
                "Stet needs Input Monitoring or Accessibility permission to paste text automatically. Text has been copied to clipboard."
        case .pasteVerificationUnavailable:
            return
                "Stet could not verify the paste because the target app did not expose enough text metadata. Text has been copied to clipboard."
        case .pasteVerificationFailed:
            return "Could not verify text was pasted successfully. Text has been copied to clipboard as a fallback."
        case .unknown(let message):
            return message
        }
    }

    var preservesRecoveredTextInClipboard: Bool {
        switch self {
        case .autoPastePermissionMissing, .pasteVerificationUnavailable, .pasteVerificationFailed:
            return true
        default:
            return false
        }
    }

    var isInsufficientFunds: Bool {

        if case .providerAPI(_, let statusCode, _) = self, statusCode == 402 {
            return true
        }
        return false
    }

    var surfaceErrorMessage: String {
        if isInsufficientFunds {
            return "Monthly quota reached."
        }
        return "Something went wrong."
    }

    var errorDescription: String? {
        message
    }

    static func from(_ error: any Error) -> Self {
        if let failure = error as? Self {
            return failure
        }

        if let speechError = error as? SpeechServiceError {
            switch speechError {
            case .microphonePermissionDenied:
                return .microphonePermissionDenied
            case .unsupportedLocale:
                return .unsupportedLocale
            case .unsupportedAudioFormat:
                return .unsupportedAudioFormat
            case .failedToStart:
                return .failedToStart
            case .emptyTranscription:
                return .emptyTranscription
            case .alreadyRecording:
                return .alreadyRecording
            case .notRecording:
                return .notRecording
            }
        }

        if let openAIError = error as? OpenAIError {
            switch openAIError {
            case .missingAPIKey(let provider):
                return .missingAPIKey(provider: provider)
            case .invalidBaseURL(let provider):
                return .invalidBaseURL(provider: provider)
            case .invalidResponse(let provider):
                return .invalidResponse(provider: provider)
            case .api(let provider, let statusCode, let message):
                return .providerAPI(provider: provider, statusCode: statusCode, message: message)
            case .missingTranscriptionText, .missingRewriteText:
                return .invalidResponse(provider: .openAI)
            case .fileNotFound(let url):
                return .unknown(message: "The audio file could not be found at \(url.path).")
            }
        }

        if let configurationError = error as? ProviderConfigurationError {
            switch configurationError {
            case .missingRequirements(let requirements):
                return .missingProviderConfiguration(requirements: requirements)
            }
        }

        if let localWhisperError = error as? LocalWhisperError {
            switch localWhisperError {
            case .modelDirectoryUnavailable, .runtimeUnavailable:
                return .localWhisperRuntimeUnavailable
            case .modelMissing(let expectedURL):
                return .localWhisperModelMissing(expectedPath: expectedURL.path)
            case .audioPreparationFailed, .transcriptionFailed, .downloadFailed, .invalidDownloadResponse:
                return .unknown(message: localWhisperError.localizedDescription)
            }
        }

        if let urlError = error as? URLError {
            return .network(code: urlError.code, message: urlError.localizedDescription)
        }

        let message = (error as? LocalizedError)?.errorDescription?.trimmingCharacters(in: .whitespacesAndNewlines)
        let localizedDescription = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return .unknown(message: message?.isEmpty == false ? message! : localizedDescription)
    }
}
