import Foundation
import OpenAI

enum OpenAISDKErrorMapper {
    nonisolated static func map(
        _ error: any Error,
        responseStatusCode: Int?,
        provider: DictationProvider
    ) -> any Error {
        if let error = error as? OpenAIError {
            return error
        }

        if let error = error as? APIErrorResponse {
            return OpenAIError.api(
                provider: provider,
                statusCode: responseStatusCode,
                message: error.error.message
            )
        }

        if error is DecodingError {
            if let responseStatusCode, responseStatusCode >= 400 {
                return OpenAIError.api(
                    provider: provider,
                    statusCode: responseStatusCode,
                    message: HTTPURLResponse.localizedString(forStatusCode: responseStatusCode)
                )
            }
            return OpenAIError.invalidResponse(provider: provider)
        }

        return error
    }
}
