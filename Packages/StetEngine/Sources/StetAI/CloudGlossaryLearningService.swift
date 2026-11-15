import Foundation
import OpenAI
import StetCore
import StetRewrite

public extension RewriteProviderConfiguration {
    nonisolated var minimumEffortForGlossaryLearning: RewriteProviderConfiguration {
        let minimumLevel: RewriteThinkingLevel?
        switch provider {
        case .deepSeek:
            minimumLevel = .off
        case .openAI:
            minimumLevel = .minimal
        case .google:
            minimumLevel = .low
        default:
            minimumLevel = nil
        }

        return RewriteProviderConfiguration(
            provider: provider,
            model: model,
            backend: backend,
            thinkingLevel: minimumLevel
        )
    }
}

public struct CloudGlossaryLearningService: GlossaryLearningService {
    public static let defaultTimeoutInterval: TimeInterval = 10

    private let configuration: RewriteProviderConfiguration
    private let session: URLSession
    private let timeoutInterval: TimeInterval

    public nonisolated init(
        configuration: RewriteProviderConfiguration,
        session: URLSession = .shared,
        timeoutInterval: TimeInterval = CloudGlossaryLearningService.defaultTimeoutInterval
    ) {
        self.configuration = configuration.minimumEffortForGlossaryLearning
        self.session = session
        self.timeoutInterval = timeoutInterval
    }

    public func extractTerms(from pair: CorrectionEditPair) async throws -> [String] {
        let rawOutput: String
        switch configuration.backend {
        case .remote(let endpoint):
            rawOutput = try await extractFromOpenAICompatible(endpoint: endpoint, pair: pair)
        case .google(let apiKey):
            rawOutput = try await extractFromGoogle(apiKey: apiKey, pair: pair)
        case .anthropic(let apiKey):
            rawOutput = try await extractFromAnthropic(apiKey: apiKey, pair: pair)
        case .appleIntelligence:
            return []
        }

        return try GlossaryLearningOutputDecoder.decodeValidatedTerms(from: rawOutput, pair: pair)
    }

    private func extractFromOpenAICompatible(
        endpoint: OpenAICompatibleProviderEndpointConfiguration,
        pair: CorrectionEditPair
    ) async throws -> String {
        let clientFactory = OpenAISDKClientFactory(endpoint: endpoint, session: session)
        let systemPrompt = GlossaryLearningPrompt.systemPrompt
        let userPrompt = GlossaryLearningPrompt.userPrompt(for: pair)

        if endpoint.provider == .openAI {
            let context = try clientFactory.makeRequestContext(timeoutInterval: timeoutInterval)
            let messages: [InputItem] = [
                .inputMessage(EasyInputMessage(role: .system, content: .textInput(systemPrompt))),
                .inputMessage(EasyInputMessage(role: .user, content: .textInput(userPrompt))),
            ]

            do {
                let response = try await context.client.responses.createResponse(
                    query: CreateModelResponseQuery(
                        input: .inputItemList(messages),
                        model: configuration.model,
                        reasoning: .init(effort: .minimal),
                        store: configuration.supportsResponsesStore ? false : nil,
                        text: .jsonSchema(
                            .init(
                                name: GlossaryLearningOutput.schemaName,
                                schema: .dynamicJsonSchema(GlossaryLearningOutput.jsonSchema),
                                description: GlossaryLearningOutput.schemaDescription,
                                strict: true
                            )
                        ),
                        user: GlossaryLearningPrompt.cacheAffinityKey
                    )
                )

                if let outputText = response.stetOutputText {
                    return outputText
                }
                if let responseData = context.responseData,
                    let recovered = Self.extractResponsesOutputText(from: responseData)
                {
                    return recovered
                }
                throw OpenAIError.invalidResponse(provider: endpoint.provider)
            } catch {
                if error is DecodingError,
                    let responseData = context.responseData,
                    let recovered = Self.extractResponsesOutputText(from: responseData)
                {
                    return recovered
                }
                throw context.mapError(error)
            }
        }

        let context = try clientFactory.makeRequestContext(
            additionalHeaders: ["Accept": "application/json"],
            additionalMiddlewares: [
                ChatCompletionsCompatibility(
                    provider: endpoint.provider,
                    thinkingLevel: configuration.thinkingLevel,
                    baseURL: endpoint.baseURL,
                    cacheAffinityKey: GlossaryLearningPrompt.cacheAffinityKey
                )
            ],
            timeoutInterval: timeoutInterval
        )

        let responseFormat: ChatQuery.ResponseFormat
        if endpoint.provider == .groq, configuration.model.lowercased().hasPrefix("openai/gpt-oss-") {
            responseFormat = .jsonSchema(
                .init(
                    name: GlossaryLearningOutput.schemaName,
                    description: GlossaryLearningOutput.schemaDescription,
                    schema: .dynamicJsonSchema(GlossaryLearningOutput.jsonSchema),
                    strict: true
                )
            )
        } else {
            responseFormat = .jsonObject
        }

        let response: ChatResult
        do {
            response = try await context.client.chats(
                query: ChatQuery(
                    messages: [
                        .system(.init(content: .textContent(systemPrompt))),
                        .user(.init(content: .string(userPrompt))),
                    ],
                    model: configuration.model,
                    reasoningEffort: nil,
                    responseFormat: responseFormat,
                    user: GlossaryLearningPrompt.cacheAffinityKey
                )
            )
        } catch {
            if context.responseStatusCode != nil {
                try ChatCompletionsCompatibility.validateResponse(context, provider: endpoint.provider)
            }
            if error is DecodingError || error is APIErrorResponse {
                return try ChatCompletionsCompatibility.recoverText(
                    from: context.responseData,
                    provider: endpoint.provider
                )
            }
            throw context.mapError(error)
        }

        try ChatCompletionsCompatibility.validateResponse(context, provider: endpoint.provider)
        for choice in response.choices {
            if let text = choice.message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
                !text.isEmpty
            {
                return text
            }
        }
        throw OpenAIError.invalidResponse(provider: endpoint.provider)
    }

    private func extractFromGoogle(apiKey: String, pair: CorrectionEditPair) async throws -> String {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let urlString =
            "https://generativelanguage.googleapis.com/v1beta/models/\(configuration.model):generateContent?key=\(trimmedKey)"
        guard !trimmedKey.isEmpty, let url = URL(string: urlString) else {
            throw GoogleError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeoutInterval
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            GoogleGlossaryRequest(
                contents: [
                    .init(role: "user", parts: [.init(text: GlossaryLearningPrompt.userPrompt(for: pair))])
                ],
                systemInstruction: .init(
                    role: nil,
                    parts: [.init(text: GlossaryLearningPrompt.systemPrompt)]
                ),
                generationConfig: .init(thinkingLevel: configuration.thinkingLevel)
            )
        )

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw GoogleError.invalidResponse
        }

        let decoded = try JSONDecoder().decode(GoogleGlossaryResponse.self, from: data)
        guard let text = decoded.candidates.first?.content.parts.first?.text else {
            throw GoogleError.missingContent
        }
        return text
    }

    private func extractFromAnthropic(apiKey: String, pair: CorrectionEditPair) async throws -> String {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw AnthropicError.invalidResponse
        }

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = timeoutInterval
        request.setValue(trimmedKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            AnthropicGlossaryRequest(
                model: configuration.model,
                system: GlossaryLearningPrompt.systemPrompt,
                messages: [.init(role: "user", content: GlossaryLearningPrompt.userPrompt(for: pair))]
            )
        )

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw AnthropicError.invalidResponse
        }

        let decoded = try JSONDecoder().decode(AnthropicGlossaryResponse.self, from: data)
        guard let text = decoded.content.first(where: { $0.type == "text" })?.text else {
            throw AnthropicError.missingContent
        }
        return text
    }

    private static func extractResponsesOutputText(from responseData: Data) -> String? {
        guard let payload = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
            let output = payload["output"] as? [[String: Any]]
        else { return nil }

        for item in output {
            guard let content = item["content"] as? [[String: Any]] else { continue }
            for block in content {
                guard let type = block["type"] as? String,
                    type == "output_text",
                    let text = block["text"] as? String
                else { continue }
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }
}

private struct GoogleGlossaryRequest: Encodable {
    struct Content: Encodable {
        let role: String?
        let parts: [Part]
    }

    struct Part: Encodable, Decodable {
        let text: String
    }

    struct GenerationConfig: Encodable {
        struct ThinkingConfig: Encodable {
            let thinkingLevel: String
        }

        let maxOutputTokens = 256
        let responseMimeType = "application/json"
        let responseJsonSchema = GlossaryLearningOutput.jsonSchema
        let thinkingConfig: ThinkingConfig?

        init(thinkingLevel: RewriteThinkingLevel?) {
            switch thinkingLevel {
            case .low, .medium, .high:
                thinkingConfig = ThinkingConfig(thinkingLevel: thinkingLevel?.rawValue ?? "low")
            default:
                thinkingConfig = nil
            }
        }
    }

    let contents: [Content]
    let systemInstruction: Content
    let generationConfig: GenerationConfig

    enum CodingKeys: String, CodingKey {
        case contents
        case systemInstruction = "system_instruction"
        case generationConfig
    }
}

private struct GoogleGlossaryResponse: Decodable {
    struct Candidate: Decodable {
        struct Content: Decodable {
            let parts: [GoogleGlossaryRequest.Part]
        }
        let content: Content
    }
    let candidates: [Candidate]
}

private struct AnthropicGlossaryRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    struct OutputConfiguration: Encodable {
        struct Format: Encodable {
            let type = "json_schema"
            let schema = GlossaryLearningOutput.jsonSchema
        }
        let format = Format()
    }

    let model: String
    let system: String
    let messages: [Message]
    let maxTokens = 256
    let outputConfig = OutputConfiguration()

    enum CodingKeys: String, CodingKey {
        case model, system, messages
        case maxTokens = "max_tokens"
        case outputConfig = "output_config"
    }
}

private struct AnthropicGlossaryResponse: Decodable {
    struct Content: Decodable {
        let type: String
        let text: String?
    }
    let content: [Content]
}
