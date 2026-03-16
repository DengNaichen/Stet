import Foundation

enum OpenAIError: LocalizedError, Equatable {
    case missingAPIKey
    case invalidBaseURL
    case fileNotFound(URL)
    case invalidResponse
    case api(statusCode: Int, message: String)
    case missingTranscriptionText
    case missingRewriteText
    case missingTranslationText

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "An OpenAI API key is required before making a cloud request."
        case .invalidBaseURL:
            return "The OpenAI base URL is invalid."
        case .fileNotFound(let url):
            return "The audio file could not be found at \(url.path)."
        case .invalidResponse:
            return "The OpenAI API returned an invalid response."
        case .api(let statusCode, let message):
            return "OpenAI API error (\(statusCode)): \(message)"
        case .missingTranscriptionText:
            return "The transcription response did not contain any text."
        case .missingRewriteText:
            return "The rewrite response did not contain any output text."
        case .missingTranslationText:
            return "The translation response did not contain any output text."
        }
    }
}
