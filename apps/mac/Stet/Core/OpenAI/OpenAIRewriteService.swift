import Foundation
import OpenAI

struct TextRewriteRequest: Sendable, Equatable {
    var sourceText: String
    var instruction: String
    var systemPrompt: String?
    var additionalUserContext: String?
    var model: String?

    nonisolated static func cleanup(
        _ sourceText: String,
        preferredSpellings: [String] = []
    ) -> Self {
        var systemPrompt = "You rewrite dictated speech into polished text. Return only the rewritten text."

        if !preferredSpellings.isEmpty {
            systemPrompt += " Preserve the exact spelling of these names, brands, jargon, and technical terms when they appear or are clearly intended: \(preferredSpellings.joined(separator: ", "))."
        }

        return Self(
            sourceText: sourceText,
            instruction: "Rewrite the dictated text so it reads cleanly while preserving the original meaning, tone, and detail.",
            systemPrompt: systemPrompt,
            additionalUserContext: nil,
            model: nil
        )
    }

    nonisolated static func rewriteSelection(
        sourceText: String,
        instruction: String,
        preferredSpellings: [String] = []
    ) -> Self {
        var systemPrompt = "You rewrite selected text according to the user's spoken instruction. Return only the rewritten text."

        if !preferredSpellings.isEmpty {
            systemPrompt += " Preserve the exact spelling of these names, brands, jargon, and technical terms when they appear or are clearly intended: \(preferredSpellings.joined(separator: ", "))."
        }

        return Self(
            sourceText: sourceText,
            instruction: instruction,
            systemPrompt: systemPrompt,
            additionalUserContext: nil,
            model: nil
        )
    }
}

protocol TextRewriteService: Sendable {
    func rewrite(_ request: TextRewriteRequest) async throws -> String
}

struct TextTranslationRequest: Sendable, Equatable {
    var sourceText: String
    var targetLanguage: TranslationTargetLanguage
    var systemPrompt: String?
    var additionalUserContext: String?
    var model: String?

    nonisolated static func translate(
        _ sourceText: String,
        to targetLanguage: TranslationTargetLanguage
    ) -> Self {
        Self(
            sourceText: sourceText,
            targetLanguage: targetLanguage,
            systemPrompt: "You translate text into \(targetLanguage.instructionName). Return only the translated text.",
            additionalUserContext: nil,
            model: nil
        )
    }
}

protocol TextTranslationService: Sendable {
    func translate(_ request: TextTranslationRequest) async throws -> String
}

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
