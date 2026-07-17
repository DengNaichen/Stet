import Foundation

enum OpenAIError: LocalizedError, Equatable {
    case missingAPIKey(provider: DictationProvider)
    case invalidBaseURL(provider: DictationProvider)
    case fileNotFound(URL)
    case invalidResponse(provider: DictationProvider)
    case api(provider: DictationProvider, statusCode: Int?, message: String)
    case missingTranscriptionText
    case missingRewriteText

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let provider):
            return "A \(provider.displayName) API key is required before making a cloud request."
        case .invalidBaseURL(let provider):
            return "The \(provider.displayName) base URL is invalid."
        case .fileNotFound(let url):
            return "The audio file could not be found at \(url.path)."
        case .invalidResponse(let provider):
            return "The \(provider.displayName) API returned an invalid response."
        case .api(let provider, let statusCode, let message):
            guard let statusCode else {
                return "\(provider.displayName) API error: \(message)"
            }
            return "\(provider.displayName) API error (\(statusCode)): \(message)"
        case .missingTranscriptionText:
            return "The transcription response did not contain any text."
        case .missingRewriteText:
            return "The rewrite response did not contain any output text."
        }
    }
}
