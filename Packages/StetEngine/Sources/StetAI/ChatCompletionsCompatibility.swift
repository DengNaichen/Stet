import Foundation
import OpenAI
import StetCore

/// Provider differences not represented by MacPaw's Chat Completions models.
struct ChatCompletionsCompatibility: OpenAIMiddleware {
    let provider: DictationProvider
    let thinkingLevel: RewriteThinkingLevel?
    let baseURL: URL
    let cacheAffinityKey: String

    func intercept(request: URLRequest) -> URLRequest {
        var request = request
        // SDK URL reconstruction double-escapes encoded paths and drops query
        // parameters. Preserve the original endpoint URL, including explicit ports.
        request.url = baseURL.appendingPathComponent("chat/completions")
        // OpenAI scoping headers were never sent to compatible providers.
        request.setValue(nil, forHTTPHeaderField: "OpenAI-Organization")
        request.setValue(nil, forHTTPHeaderField: "OpenAI-Project")
        guard provider == .deepSeek,
            let data = request.httpBody,
            var body = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return request }
        body["thinking"] = ["type": thinkingLevel == .off ? "disabled" : "enabled"]
        body["prompt_cache_key"] = cacheAffinityKey
        guard let encoded = try? JSONSerialization.data(withJSONObject: body) else { return request }
        request.httpBody = encoded
        return request
    }

    // The SDK's typed chats path decodes without checking HTTP status. Check both
    // success and failure paths, including error responses shaped like ChatResult.
    static func validateResponse(
        _ context: OpenAISDKRequestContext,
        provider: DictationProvider
    ) throws {
        guard let status = context.responseStatusCode else {
            throw OpenAIError.invalidResponse(provider: provider)
        }
        guard (200...299).contains(status) else {
            let payload = context.responseData.flatMap {
                try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
            }
            let error = payload?["error"] as? [String: Any]
            let message = (error?["message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw OpenAIError.api(
                provider: provider,
                statusCode: status,
                message: message.flatMap { $0.isEmpty ? nil : $0 }
                    ?? HTTPURLResponse.localizedString(forStatusCode: status)
            )
        }
    }

    // Some compatible endpoints omit metadata required by ChatResult even with
    // relaxed parsing. Recover only the business shape accepted before migration,
    // from the recorded response of the same request; never issue a second request.
    static func recoverText(from data: Data?, provider: DictationProvider) throws -> String {
        guard let data,
            let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = payload["choices"] as? [[String: Any]]
        else { throw OpenAIError.invalidResponse(provider: provider) }

        var firstText: String?
        for choice in choices {
            guard let message = choice["message"] as? [String: Any] else {
                throw OpenAIError.invalidResponse(provider: provider)
            }
            let content = message["content"]
            if content == nil || content is NSNull { continue }
            guard let content = content as? String else {
                throw OpenAIError.invalidResponse(provider: provider)
            }
            let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
            if firstText == nil && !text.isEmpty { firstText = text }
        }
        guard let firstText else { throw OpenAIError.missingRewriteText }
        return firstText
    }
}
