import Foundation
import StetCore
import StetRewrite
import OpenAI

public struct OpenAIRewriteService: TextRewriteService {
    private static let prewarmTimeoutInterval: TimeInterval = 10

    private let clientFactory: OpenAISDKClientFactory
    private let endpoint: OpenAICompatibleProviderEndpointConfiguration
    private let session: URLSession
    private let defaultModel: String
    private let supportsResponsesStore: Bool
    private let thinkingLevel: RewriteThinkingLevel?

    public nonisolated init(
        configuration: RewriteProviderConfiguration,
        session: URLSession = .shared
    ) {
        guard case .remote(let endpoint) = configuration.backend else {
            preconditionFailure("OpenAIRewriteService requires a remote rewrite configuration.")
        }

        self.clientFactory = OpenAISDKClientFactory(endpoint: endpoint, session: session)
        self.endpoint = endpoint
        self.session = session
        self.defaultModel = configuration.model
        self.supportsResponsesStore = configuration.supportsResponsesStore
        self.thinkingLevel = configuration.thinkingLevel
    }

    public func prewarm(_ request: TextRewriteRequest) async {
        let trimmedKey = endpoint.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard endpoint.provider == .custom || !trimmedKey.isEmpty else { return }

        var urlRequest = URLRequest(url: endpoint.baseURL.appendingPathComponent("models"))
        urlRequest.httpMethod = "GET"
        urlRequest.timeoutInterval = Self.prewarmTimeoutInterval
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")

        if !trimmedKey.isEmpty {
            urlRequest.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        }
        if endpoint.provider == .openAI {
            if let organizationID = endpoint.organizationID?.trimmingCharacters(in: .whitespacesAndNewlines),
                !organizationID.isEmpty
            {
                urlRequest.setValue(organizationID, forHTTPHeaderField: "OpenAI-Organization")
            }
            if let projectID = endpoint.projectID?.trimmingCharacters(in: .whitespacesAndNewlines),
                !projectID.isEmpty
            {
                urlRequest.setValue(projectID, forHTTPHeaderField: "OpenAI-Project")
            }
        }

        _ = try? await session.data(for: urlRequest)
    }

    public func rewrite(_ request: TextRewriteRequest) async throws -> String {
        let prepared = PreparedCloudRewritePayload(request: request)
        if endpoint.provider != .openAI {
            return try await rewriteWithChatCompletions(request: request, prepared: prepared)
        }

        let messages = makeMessages(
            systemPrompt: prepared.systemPrompt,
            userPrompt: prepared.userPrompt
        )
        let requestContext = try clientFactory.makeRequestContext()

        do {
            let response = try await requestContext.client.responses.createResponse(
                query: CreateModelResponseQuery(
                    input: .inputItemList(messages),
                    model: request.model ?? defaultModel,
                    reasoning: .init(effort: openAIReasoningEffort),
                    store: supportsResponsesStore ? false : nil,
                    text: .jsonSchema(
                        .init(
                            name: StructuredRewriteOutput.schemaName,
                            schema: .dynamicJsonSchema(StructuredRewriteOutput.jsonSchema),
                            description: StructuredRewriteOutput.schemaDescription,
                            strict: true
                        )
                    ),
                    user: prepared.cacheAffinityKey
                )
            )

            if let outputText = response.stetOutputText {
                return try Self.decodeStructuredText(outputText, provider: endpoint.provider)
            }

            if let responseData = requestContext.responseData,
                let recoveredText = Self.extractOutputText(from: responseData)
            {
                return try Self.decodeStructuredText(recoveredText, provider: endpoint.provider)
            }

            throw OpenAIError.missingRewriteText
        } catch {
            if error is DecodingError,
                let responseData = requestContext.responseData,
                let recoveredText = Self.extractOutputText(from: responseData)
            {
                return try Self.decodeStructuredText(recoveredText, provider: endpoint.provider)
            }

            throw requestContext.mapError(error)
        }
    }

    private func rewriteWithChatCompletions(
        request: TextRewriteRequest,
        prepared: PreparedCloudRewritePayload
    ) async throws -> String {
        let model = request.model ?? defaultModel
        let context = try clientFactory.makeRequestContext(
            additionalHeaders: ["Accept": "application/json"],
            additionalMiddlewares: [
                ChatCompletionsCompatibility(
                    provider: endpoint.provider,
                    thinkingLevel: thinkingLevel,
                    baseURL: endpoint.baseURL,
                    cacheAffinityKey: prepared.cacheAffinityKey
                )
            ]
        )
        let response: ChatResult
        do {
            response = try await context.client.chats(
                query: ChatQuery(
                    messages: [
                        .system(.init(content: .textContent(prepared.systemPrompt))),
                        .user(.init(content: .string(prepared.userPrompt))),
                    ],
                    model: model,
                    reasoningEffort: deepSeekReasoningEffort,
                    responseFormat: chatResponseFormat(model: model),
                    user: prepared.cacheAffinityKey
                )
            )
        } catch {
            // Transport failures have no response; preserve cancellation and timeout as-is.
            if context.responseStatusCode != nil {
                try ChatCompletionsCompatibility.validateResponse(context, provider: endpoint.provider)
            }
            if error is DecodingError || error is APIErrorResponse {
                let text = try ChatCompletionsCompatibility.recoverText(
                    from: context.responseData, provider: endpoint.provider
                )
                return try Self.decodeStructuredText(text, provider: endpoint.provider)
            }
            throw context.mapError(error)
        }

        try ChatCompletionsCompatibility.validateResponse(context, provider: endpoint.provider)
        for choice in response.choices {
            guard let text = choice.message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
                !text.isEmpty
            else { continue }
            return try Self.decodeStructuredText(text, provider: endpoint.provider)
        }
        throw OpenAIError.missingRewriteText
    }

    private func chatResponseFormat(model: String) -> ChatQuery.ResponseFormat {
        guard endpoint.provider == .groq, model.lowercased().hasPrefix("openai/gpt-oss-") else {
            return .jsonObject
        }
        return .jsonSchema(
            .init(
                name: StructuredRewriteOutput.schemaName,
                description: StructuredRewriteOutput.schemaDescription,
                schema: .dynamicJsonSchema(StructuredRewriteOutput.jsonSchema),
                strict: true
            )
        )
    }

    private var openAIReasoningEffort: Components.Schemas.ReasoningEffort? {
        switch thinkingLevel {
        case .minimal: return .minimal
        case .low: return .low
        case .medium: return .medium
        case .high: return .high
        default: return nil
        }
    }

    private var deepSeekReasoningEffort: ChatQuery.ReasoningEffort? {
        guard endpoint.provider == .deepSeek, thinkingLevel != .off else { return nil }
        switch thinkingLevel {
        case .low: return .low
        case .high: return .high
        case .max: return .customValue("max")
        default: return nil
        }
    }

    private func makeMessages(
        systemPrompt: String?,
        userPrompt: String
    ) -> [InputItem] {
        var messages: [InputItem] = []

        if let systemPrompt, !systemPrompt.isEmpty {
            messages.append(
                .inputMessage(
                    EasyInputMessage(role: .system, content: .textInput(systemPrompt))
                )
            )
        }

        messages.append(
            .inputMessage(
                EasyInputMessage(role: .user, content: .textInput(userPrompt))
            )
        )
        return messages
    }

    private static func extractOutputText(from responseData: Data) -> String? {
        guard let payload = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
            let output = payload["output"] as? [[String: Any]]
        else {
            return nil
        }

        for item in output {
            guard let content = item["content"] as? [[String: Any]] else {
                continue
            }

            for block in content {
                guard let type = block["type"] as? String,
                    type == "output_text",
                    let text = block["text"] as? String
                else {
                    continue
                }

                let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedText.isEmpty {
                    return trimmedText
                }
            }
        }

        return nil
    }

    private static func decodeStructuredText(
        _ content: String,
        provider: DictationProvider
    ) throws -> String {
        do {
            return try StructuredRewriteOutputDecoder.decodeText(from: content)
        } catch StructuredRewriteOutputError.emptyText {
            throw OpenAIError.missingRewriteText
        } catch {
            throw OpenAIError.invalidResponse(provider: provider)
        }
    }

}
