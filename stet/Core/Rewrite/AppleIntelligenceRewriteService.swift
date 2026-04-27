import Foundation
import FoundationModels

enum AppleIntelligenceRewriteError: LocalizedError, Equatable, Sendable {
    case unavailable(String)
    case emptyOutput

    nonisolated var errorDescription: String? {
        switch self {
        case .unavailable(let reason):
            return "Apple Intelligence refine is unavailable: \(reason)."
        case .emptyOutput:
            return "Apple Intelligence refine returned empty text."
        }
    }
}

@Generable
struct RewriteResult {
    @Guide(description: "The cleaned, properly punctuated transcript")
    let text: String
}

public struct AppleIntelligenceRewriteService: TextRewriteService {
    private let sessionStore = AppleIntelligenceRewriteSessionStore()

    public init() {}

    func prewarm(_ request: TextRewriteRequest) async {
        guard Self.isAvailable else { return }
        await sessionStore.prewarm(
            instructions: Self.instructions(for: request),
            promptPrefix: Self.promptPrefix(additionalContext: request.additionalContext)
        )
    }

    func rewrite(_ request: TextRewriteRequest) async throws -> String {
        guard Self.isAvailable else {
            throw AppleIntelligenceRewriteError.unavailable(Self.availabilityDescription)
        }

        let output = try await sessionStore.respond(
            instructions: Self.instructions(for: request),
            prompt: Self.prompt(for: request)
        )
        let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOutput.isEmpty else {
            throw AppleIntelligenceRewriteError.emptyOutput
        }
        return trimmedOutput
    }

    public static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability {
            return true
        }
        return false
    }

    public static var availabilityDescription: String {
        switch SystemLanguageModel.default.availability {
        case .available:
            return "available"
        case .unavailable(let reason):
            return String(describing: reason)
        }
    }

    private nonisolated static func instructions(for request: TextRewriteRequest) -> String {
        let base = LocalRewritePromptBuilder.systemPrompt(
            audience: request.audience ?? .ai,
            preferredSpellings: request.preferredSpellings
        )

        var reminder = """
            Reminder:
            Be aggressive with punctuation.
            Apply transcript cleanup when any cleanup is available.
            If the input contains filler words, repeated words, missing punctuation, missing capitalization, return the cleaned version.
            Be thorough about filler removal. Remove these whenever they are used as verbal scaffolding:
            - Chinese: 那个 这个 就是 然后 嗯 呃 啊 哎 你知道 我跟你说 怎么说 反正
            - English: um, uh, er, ah, like, you know, I mean, basically, actually, sort of, kind of, right
            Fix obvious ASR recognition errors when the context makes the intended word clear.
            For example, in an App Store payment context, "寄费的逻辑" should become "计费逻辑",

            Do not translate the transcript, Company name, Terminology, into another language.
            """
        if let languageCode = request.languageCode {
            reminder += "\nThe speaker's primary language is \(languageCode)."
        }

        return """
            \(base)

            ### Category 1 — Remove Filler Words and Noise:

            Input: "就是,那个,那个我的意思是把那个 button 改一下。"
            Output: "我的意思是，把那个 button 改一下。"

            Input: "呃……就是……你……你觉得……你觉得这个模型现在是ok的吗？"
            Output: "你觉得这个模型现在是 ok 的吗？"

            Input: "我……我想……那个……看看这个……这个逻辑。"
            Output: "我想看看这个逻辑。"

            Input: "这个小模型它都不敢动，你知道吗？它就特别特别的……嗯……怎么说……胆子特别小"
            Output: "这个小模型它都不敢动，你知道吗？它就胆子特别小"

            ### Category 2 — Self-Correction and Logic:
            Input: "我们明天去北京，啊不对不对不对，我们明天去上海吧。"
            Output: "我们明天去上海吧。"

            Input: "就是那个，我刚才其实是想说，呃，那个，就是那个，我们明天开会，哎呀不对，是后天，后天三点开会吧。"
            Output: "我们后天三点开会吧。"

            ### Category 3 - Fix ASR error:
            Input: "但是呢我需要在现在app store里面做一个这种寄费的逻辑, 但是我不知道怎么寄"
            Output: "但是呢我需要在App Store里面做一个这种计费的逻辑, 但是我不知道怎么计"

            \(reminder)
            """
    }

    private nonisolated static func promptPrefix(additionalContext: String?) -> String {
        var prefix = """
            Instruction:
            Clean the following raw transcription according to your instructions.

            """

        if let additionalContext = additionalContext?.trimmingCharacters(in: .whitespacesAndNewlines),
            !additionalContext.isEmpty
        {
            prefix = """
                Context:
                \(additionalContext)

                \(prefix)
                """
        }

        return prefix + "Text:\n"
    }

    private nonisolated static func prompt(for request: TextRewriteRequest) -> String {
        promptPrefix(additionalContext: request.additionalContext)
            + request.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private actor AppleIntelligenceRewriteSessionStore {
    private var activeSession: LanguageModelSession?

    func prewarm(instructions: String, promptPrefix: String) {
        // Create and store the session for reuse
        let session = Self.makeSession(instructions: instructions)
        session.prewarm(promptPrefix: Prompt(promptPrefix))
        self.activeSession = session
    }

    func respond(instructions: String, prompt: String) async throws -> String {
        // Use the prewarmed session if available, otherwise fall back to a fresh one
        let session: LanguageModelSession
        if let active = activeSession {
            session = active
            activeSession = nil  // Consume the session
        } else {
            session = Self.makeSession(instructions: instructions)
        }

        let response = try await session.respond(
            to: Prompt(prompt),
            generating: RewriteResult.self
        )
        return response.content.text
    }

    private static func makeSession(instructions: String) -> LanguageModelSession {
        let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
        return LanguageModelSession(model: model, instructions: instructions)
    }
}
