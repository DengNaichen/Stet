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

        // Core mandate: faithful reproduction, not transformation.
        // Keep tone neutral — aggressive DO NOT / NEVER phrasing triggers safety refusals
        // on small on-device models even with permissive guardrails.
        var languageLaw = """
            Your only job is to clean up raw speech-to-text output into readable text.
            Output the transcript in the exact language(s) the speaker used. Never translate.
            If the speaker mixed languages in one sentence, preserve that exact mix.
            Remove filler words, false starts, and repetitive reformulations — keep only the final intended meaning. Fix obvious speech-recognition errors.
            Output plain text only — no Markdown, no lists, no commentary.
            Reproduce any casual or informal language exactly as spoken.
            """
        if let languageCode = request.languageCode {
            languageLaw += "\nThe speaker's primary language is \(languageCode)."
        }

        return """
            \(languageLaw)

            \(base)

            ### Example 1 — remove filler words (Chinese):
            Input: "那个，我今天觉得天气，嗯，挺好的，我们出去走走吧。"
            Output: "我今天觉得天气挺好的，我们出去走走吧。"

            Input: "就是那个那个呃就是那个,我的意思是把那个 button 改一下。"
            Output: "我的意思是, 把那个 button 改一下。"

            ### Example 2 — preserve mixed Chinese-English exactly:
            Input: "这个coreml model的performance还可以。"
            Output: "这个 CoreML model 的 performance 还可以。"

            ### Example 3 — reproduce casual / informal language unchanged:
            Input: "我靠这个bug也太离谱了，你他妈帮我看看这个 stack trace 是什么意思。"
            Output: "我靠这个bug也太离谱了，你他妈帮我看看这个 stack trace 是什么意思。"

            ### Example 4 — remove filler words (English):
            Input: "um, uh, so I think we should probably, uh, refactor this whole module."
            Output: "I think we should refactor this whole module."

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
    func prewarm(instructions: String, promptPrefix: String) {
        // Prewarming with a fresh session so the model weights are hot by the time
        // the real rewrite request arrives. We do NOT cache the session — each
        // dictation rewrite is independent and must not inherit prior conversation history.
        let session = Self.makeSession(instructions: instructions)
        session.prewarm(promptPrefix: Prompt(promptPrefix))
    }

    func respond(instructions: String, prompt: String) async throws -> String {
        // Always create a fresh session to prevent conversation history from a previous
        // dictation round from leaking into the current rewrite (language pollution).
        let session = Self.makeSession(instructions: instructions)
        let response = try await session.respond(to: Prompt(prompt))
        return response.content
    }

    private static func makeSession(instructions: String) -> LanguageModelSession {
        let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
        return LanguageModelSession(model: model, instructions: instructions)
    }
}
