import Foundation
import OpenAI

struct OpenAIRewriteService: TextRewriteService {
    private let clientFactory: OpenAISDKClientFactory
    private let defaultModel: String
    private let supportsResponsesStore: Bool

    nonisolated init(
        configuration: OpenAIConfiguration,
        session: URLSession = .shared
    ) {
        self.clientFactory = OpenAISDKClientFactory(configuration: configuration, session: session)
        self.defaultModel = configuration.rewriteModel
        self.supportsResponsesStore = configuration.supportsResponsesStore
    }

    func rewrite(_ request: TextRewriteRequest) async throws -> String {
        let instruction = request.instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceText = request.sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        let systemPrompt = request.systemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines)
        let additionalUserContext = request.additionalUserContext?.trimmingCharacters(in: .whitespacesAndNewlines)

        let messages = makeMessages(
            systemPrompt: systemPrompt,
            additionalUserContext: additionalUserContext,
            instruction: instruction,
            sourceText: sourceText
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

            throw OpenAIError.missingRewriteText
        } catch {
            throw requestContext.mapError(error)
        }
    }

    private func makeMessages(
        systemPrompt: String?,
        additionalUserContext: String?,
        instruction: String,
        sourceText: String
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
        \(instruction)

        Text:
        \(sourceText)
        """

        if let additionalUserContext, !additionalUserContext.isEmpty {
            userPrompt = """
            Context:
            \(additionalUserContext)

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
}
