import Foundation

/// Google Gemini API 专属的重写服务实现
struct GoogleRewriteService: TextRewriteService {
    private let apiKey: String
    private let model: String
    private let session: URLSession

    nonisolated init(
        apiKey: String,
        model: String,
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.model = model
        self.session = session
    }

    func rewrite(_ request: TextRewriteRequest) async throws -> String {
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
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            throw GoogleError.invalidURL
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = GoogleGeminiRequest(
            contents: [
                GoogleContent(role: "user", parts: [GooglePart(text: userPrompt)])
            ],
            systemInstruction: GoogleContent(role: nil, parts: [GooglePart(text: systemPrompt)])
        )
        urlRequest.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GoogleError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorDetail = try? JSONDecoder().decode(GoogleErrorResponse.self, from: data)
            throw GoogleError.apiError(
                statusCode: httpResponse.statusCode,
                message: errorDetail?.error.message ?? "Unknown error"
            )
        }

        let result = try JSONDecoder().decode(GoogleGeminiResponse.self, from: data)
        guard let text = result.candidates.first?.content.parts.first?.text else {
            throw GoogleError.missingContent
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func withRetry<T>(
        attempts: Int,
        operation: () async throws -> T
    ) async throws -> T {
        for attempt in 1...attempts {
            do {
                return try await operation()
            } catch let error as GoogleError {
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
        throw GoogleError.unknown
    }
}

// MARK: - API Models

private struct GoogleGeminiRequest: Encodable {
    let contents: [GoogleContent]
    let systemInstruction: GoogleContent?
    let generationConfig: GoogleGenerationConfig = GoogleGenerationConfig()

    enum CodingKeys: String, CodingKey {
        case contents
        case systemInstruction = "system_instruction"
        case generationConfig
    }
}

private struct GoogleContent: Encodable {
    let role: String?
    let parts: [GooglePart]
}

private struct GooglePart: Encodable, Decodable {
    let text: String
}

private struct GoogleGenerationConfig: Encodable {
    let maxOutputTokens: Int = 4096
}

private struct GoogleGeminiResponse: Decodable {
    struct Candidate: Decodable {
        struct Content: Decodable {
            let parts: [GooglePart]
        }
        let content: Content
    }
    let candidates: [Candidate]
}

private struct GoogleErrorResponse: Decodable {
    struct ErrorDetail: Decodable {
        let message: String
    }
    let error: ErrorDetail
}

// MARK: - Errors

enum GoogleError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case apiError(statusCode: Int, message: String)
    case missingContent
    case unknown

    var shouldRetry: Bool {
        switch self {
        case .apiError(let statusCode, _):
            return statusCode == 429 || (statusCode >= 500 && statusCode <= 599)
        case .invalidResponse:
            return true
        default:
            return false
        }
    }

    var errorDescription: String? {
        switch self {
        case .apiError(let code, let msg):
            return "Google API Error (\(code)): \(msg)"
        case .missingContent:
            return "Gemini response missing text content"
        default:
            return "Google Gemini service encountered an error"
        }
    }
}
