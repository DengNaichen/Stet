import Foundation
import OpenAI

struct OpenAIRewriteService: TextRewriteService {
    private enum Configuration {
        static let cleanupInstruction = "Clean the following raw transcription according to your instructions."
    }

    private let clientFactory: OpenAISDKClientFactory
    private let defaultModel: String
    private let supportsResponsesStore: Bool

    nonisolated init(
        configuration: RewriteProviderConfiguration,
        session: URLSession = .shared
    ) {
        self.clientFactory = OpenAISDKClientFactory(endpoint: configuration.endpoint, session: session)
        self.defaultModel = configuration.model
        self.supportsResponsesStore = configuration.supportsResponsesStore
    }

    func rewrite(_ request: TextRewriteRequest) async throws -> String {
        let text = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let systemPrompt = LocalRewritePromptBuilder.systemPrompt(
            audience: request.audience ?? .human,
            preferredSpellings: request.preferredSpellings
        )
        let additionalContext = request.additionalContext?.trimmingCharacters(in: .whitespacesAndNewlines)

        let messages = makeMessages(
            systemPrompt: systemPrompt,
            additionalContext: additionalContext,
            text: text
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

    private func makeMessages(
        systemPrompt: String?,
        additionalContext: String?,
        text: String
    ) -> [InputItem] {
        var messages: [InputItem] = []

        if let systemPrompt, !systemPrompt.isEmpty {
            messages.append(
                .inputMessage(
                    EasyInputMessage(role: .system, content: .textInput(systemPrompt))
                )
            )
        }

        var userPrompt = """
            Instruction:
            \(Configuration.cleanupInstruction)

            Text:
            \(text)
            """

        if let additionalContext, !additionalContext.isEmpty {
            userPrompt = """
                Context:
                \(additionalContext)

                \(userPrompt)
                """
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
}
