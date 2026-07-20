import Foundation
import StetCore
import StetRewrite

public struct AnthropicRewriteService: TextRewriteService {
    private let apiKey: String
    private let model: String
    private let baseURL: URL
    private let session: URLSession

    public nonisolated init(
        apiKey: String,
        model: String,
        baseURL: URL = URL(string: "https://api.anthropic.com/v1/messages")!,
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.model = model
        self.baseURL = baseURL
        self.session = session
    }

    public func rewrite(_ request: TextRewriteRequest) async throws -> String {
        let prepared = PreparedCloudRewritePayload(request: request)

        return try await withRetry(attempts: 3) {
            try await performRewrite(
                model: request.model ?? self.model,
                systemPrompt: prepared.systemPrompt,
                userPrompt: prepared.userPrompt
            )
        }
    }

    private func performRewrite(
        model: String,
        systemPrompt: String,
        userPrompt: String
    ) async throws -> String {
        var urlRequest = URLRequest(url: baseURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = AnthropicRequest(
            model: model,
            system: systemPrompt,
            messages: [AnthropicMessage(role: "user", content: userPrompt)]
        )
        urlRequest.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AnthropicError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorDetail = try? JSONDecoder().decode(AnthropicErrorResponse.self, from: data)
            throw AnthropicError.apiError(
                statusCode: httpResponse.statusCode,
                message: errorDetail?.error.message ?? "Unknown error"
            )
        }

        let result = try JSONDecoder().decode(AnthropicResponse.self, from: data)
        guard let text = result.content.first(where: { $0.type == "text" })?.text else {
            throw AnthropicError.missingContent
        }

        do {
            return try StructuredRewriteOutputDecoder.decodeText(from: text)
        } catch StructuredRewriteOutputError.emptyText {
            throw AnthropicError.missingContent
        } catch {
            throw AnthropicError.invalidStructuredOutput
        }
    }

    private func withRetry<T>(
        attempts: Int,
        operation: () async throws -> T
    ) async throws -> T {
        for attempt in 1...attempts {
            do {
                return try await operation()
            } catch let error as AnthropicError {
                if error.shouldRetry && attempt < attempts {
                    let delay = pow(2.0, Double(attempt))
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                }
                throw error
            } catch {
                if attempt < attempts {
                    try await Task.sleep(nanoseconds: UInt64(1_000_000_000))
                    continue
                }
                throw error
            }
        }
        throw AnthropicError.unknown
    }
}

private struct AnthropicRequest: Encodable {
    let model: String
    let system: String
    let messages: [AnthropicMessage]
    let maxTokens: Int = 4096
    let outputConfig = AnthropicOutputConfiguration()

    enum CodingKeys: String, CodingKey {
        case model, system, messages
        case maxTokens = "max_tokens"
        case outputConfig = "output_config"
    }
}

private struct AnthropicOutputConfiguration: Encodable {
    struct Format: Encodable {
        let type = "json_schema"
        let schema = StructuredRewriteOutput.jsonSchema
    }

    let format = Format()
}

private struct AnthropicMessage: Encodable {
    let role: String
    let content: String
}

private struct AnthropicResponse: Decodable {
    struct Content: Decodable {
        let type: String
        let text: String?
    }
    let content: [Content]
}

private struct AnthropicErrorResponse: Decodable {
    struct ErrorDetail: Decodable {
        let message: String
    }
    let error: ErrorDetail
}

public enum AnthropicError: Error, LocalizedError {
    case invalidResponse
    case invalidStructuredOutput
    case apiError(statusCode: Int, message: String)
    case missingContent
    case unknown

    public var shouldRetry: Bool {
        switch self {
        case .apiError(let statusCode, _):
            return statusCode == 429 || (statusCode >= 500 && statusCode <= 599)
        case .invalidResponse:
            return true
        default:
            return false
        }
    }

    public var errorDescription: String? {
        switch self {
        case .apiError(let code, let msg):
            return "Anthropic API Error (\(code)): \(msg)"
        case .missingContent:
            return "Anthropic response missing text content"
        case .invalidStructuredOutput:
            return "Anthropic response did not match the rewrite output schema"
        default:
            return "Anthropic service encountered an error"
        }
    }
}
