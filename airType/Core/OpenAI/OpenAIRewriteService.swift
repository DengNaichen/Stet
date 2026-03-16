import Foundation

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
    private struct ResponsesRequest: Encodable {
        struct Message: Encodable {
            let role: String
            let content: String
        }

        let model: String
        let input: [Message]
        let store: Bool
    }

    private struct ResponsesResponse: Decodable {
        struct OutputItem: Decodable {
            struct ContentItem: Decodable {
                let type: String
                let text: String?
            }

            let type: String
            let content: [ContentItem]?
        }

        let outputText: String?
        let output: [OutputItem]?

        enum CodingKeys: String, CodingKey {
            case outputText = "output_text"
            case output
        }
    }

    private let client: OpenAIClient
    private let defaultModel: String

    nonisolated init(
        configuration: OpenAIConfiguration,
        session: URLSession = .shared
    ) {
        self.client = OpenAIClient(configuration: configuration, session: session)
        self.defaultModel = configuration.rewriteModel
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

        let response: ResponsesResponse = try await client.sendJSONRequest(
            path: "/responses",
            body: ResponsesRequest(
                model: request.model ?? defaultModel,
                input: messages,
                store: false
            )
        )

        if let outputText = response.outputText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !outputText.isEmpty {
            return outputText
        }

        if let output = response.output {
            for item in output where item.type == "message" {
                for content in item.content ?? [] where content.type == "output_text" {
                    if let text = content.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !text.isEmpty {
                        return text
                    }
                }
            }
        }

        throw OpenAIError.missingRewriteText
    }

    private func makeMessages(
        systemPrompt: String?,
        additionalUserContext: String?,
        instruction: String,
        sourceText: String
    ) -> [ResponsesRequest.Message] {
        var messages: [ResponsesRequest.Message] = []

        if let systemPrompt, !systemPrompt.isEmpty {
            messages.append(.init(role: "system", content: systemPrompt))
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

        messages.append(.init(role: "user", content: userPrompt))
        return messages
    }
}

struct OpenAITranslationService: TextTranslationService {
    private struct ResponsesRequest: Encodable {
        struct Message: Encodable {
            let role: String
            let content: String
        }

        let model: String
        let input: [Message]
        let store: Bool
    }

    private struct ResponsesResponse: Decodable {
        struct OutputItem: Decodable {
            struct ContentItem: Decodable {
                let type: String
                let text: String?
            }

            let type: String
            let content: [ContentItem]?
        }

        let outputText: String?
        let output: [OutputItem]?

        enum CodingKeys: String, CodingKey {
            case outputText = "output_text"
            case output
        }
    }

    private let client: OpenAIClient
    private let defaultModel: String

    nonisolated init(
        configuration: OpenAIConfiguration,
        session: URLSession = .shared
    ) {
        self.client = OpenAIClient(configuration: configuration, session: session)
        self.defaultModel = configuration.translationModel
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

        let response: ResponsesResponse = try await client.sendJSONRequest(
            path: "/responses",
            body: ResponsesRequest(
                model: request.model ?? defaultModel,
                input: messages,
                store: false
            )
        )

        if let outputText = response.outputText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !outputText.isEmpty {
            return outputText
        }

        if let output = response.output {
            for item in output where item.type == "message" {
                for content in item.content ?? [] where content.type == "output_text" {
                    if let text = content.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !text.isEmpty {
                        return text
                    }
                }
            }
        }

        throw OpenAIError.missingTranslationText
    }

    private func makeMessages(
        systemPrompt: String?,
        additionalUserContext: String?,
        sourceText: String,
        targetLanguage: TranslationTargetLanguage
    ) -> [ResponsesRequest.Message] {
        var messages: [ResponsesRequest.Message] = []

        if let systemPrompt, !systemPrompt.isEmpty {
            messages.append(.init(role: "system", content: systemPrompt))
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

        messages.append(.init(role: "user", content: userPrompt))
        return messages
    }
}
