import Foundation
import OpenAI

struct OpenAITranslationService: TextTranslationService {
    private let clientFactory: OpenAISDKClientFactory
    private let defaultModel: String
    private let supportsResponsesStore: Bool

    nonisolated init(
        configuration: OpenAIConfiguration,
        session: URLSession = .shared
    ) {
        self.clientFactory = OpenAISDKClientFactory(configuration: configuration, session: session)
        self.defaultModel = configuration.translationModel
        self.supportsResponsesStore = configuration.supportsResponsesStore
    }

    func translate(_ request: TextTranslationRequest) async throws -> String {
        let sourceText = request.sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        let systemPrompt = request.systemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines)
        let additionalUserContext = request.additionalUserContext?.trimmingCharacters(in: .whitespacesAndNewlines)

        let messages = makeMessages(
            systemPrompt: systemPrompt,
            additionalUserContext: additionalUserContext,
            sourceText: sourceText,
            targetLanguage: request.targetLanguage
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

            throw OpenAIError.missingTranslationText
        } catch {
            throw requestContext.mapError(error)
        }
    }

    private func makeMessages(
        systemPrompt: String?,
        additionalUserContext: String?,
        sourceText: String,
        targetLanguage: TranslationTargetLanguage
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
        Target language:
        \(targetLanguage.instructionName)

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
