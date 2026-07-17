import Foundation
import OpenAI

struct OpenAIRewriteService: TextRewriteService {
    private struct ChatCompletionMessage: Encodable {
        let role: String
        let content: String
    }

    private struct ChatCompletionRequest: Encodable {
        let model: String
        let messages: [ChatCompletionMessage]
        let thinking: ChatCompletionThinking?
    }

    private struct ChatCompletionThinking: Encodable {
        let type: String
    }

    private struct ChatCompletionResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: String?
            }

            let message: Message
        }

        let choices: [Choice]
    }

    private struct ProviderAPIErrorEnvelope: Decodable {
        let error: ProviderAPIErrorBody
    }

    private struct ProviderAPIErrorBody: Decodable {
        let message: String?
    }

    private let clientFactory: OpenAISDKClientFactory
    private let endpoint: OpenAICompatibleProviderEndpointConfiguration
    private let session: URLSession
    private let defaultModel: String
    private let supportsResponsesStore: Bool

    nonisolated init(
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
    }

    func rewrite(_ request: TextRewriteRequest) async throws -> String {
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
                    store: supportsResponsesStore ? false : nil
                )
            )

            if let outputText = response.stetOutputText {
                return outputText
            }

            if let responseData = requestContext.responseData,
                let recoveredText = Self.extractOutputText(from: responseData)
            {
                return recoveredText
            }

            throw OpenAIError.missingRewriteText
        } catch {
            if error is DecodingError,
                let responseData = requestContext.responseData,
                let recoveredText = Self.extractOutputText(from: responseData)
            {
                return recoveredText
            }

            throw requestContext.mapError(error)
        }
    }

    private func rewriteWithChatCompletions(
        request: TextRewriteRequest,
        prepared: PreparedCloudRewritePayload
    ) async throws -> String {
        let request = try makeChatCompletionsRequest(
            model: request.model ?? defaultModel,
            prepared: prepared
        )
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIError.invalidResponse(provider: endpoint.provider)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw OpenAIError.api(
                provider: endpoint.provider,
                statusCode: httpResponse.statusCode,
                message: Self.parseErrorMessage(from: data)
                    ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            )
        }

        let responsePayload: ChatCompletionResponse
        do {
            responsePayload = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        } catch {
            throw OpenAIError.invalidResponse(provider: endpoint.provider)
        }

        for choice in responsePayload.choices {
            guard let text = choice.message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
                !text.isEmpty
            else {
                continue
            }
            return text
        }

        throw OpenAIError.missingRewriteText
    }

    private func makeChatCompletionsRequest(
        model: String,
        prepared: PreparedCloudRewritePayload
    ) throws -> URLRequest {
        let trimmedKey = endpoint.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw OpenAIError.missingAPIKey(provider: endpoint.provider)
        }

        let url = Self.normalizedBaseURL(endpoint.baseURL).appendingPathComponent("chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            ChatCompletionRequest(
                model: model,
                messages: [
                    ChatCompletionMessage(role: "system", content: prepared.systemPrompt),
                    ChatCompletionMessage(role: "user", content: prepared.userPrompt),
                ],
                thinking: Self.thinkingConfiguration(for: endpoint.provider)
            )
        )
        return request
    }

    nonisolated private static func thinkingConfiguration(for provider: DictationProvider) -> ChatCompletionThinking? {
        guard provider == .deepSeek else { return nil }
        return ChatCompletionThinking(type: "disabled")
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

    private static func normalizedBaseURL(_ baseURL: URL) -> URL {
        baseURL.hasDirectoryPath ? baseURL : baseURL.appendingPathComponent("")
    }

    private static func parseErrorMessage(from data: Data) -> String? {
        let envelope = try? JSONDecoder().decode(ProviderAPIErrorEnvelope.self, from: data)
        let message = envelope?.error.message?.trimmingCharacters(in: .whitespacesAndNewlines)
        return message?.isEmpty == false ? message : nil
    }
}
