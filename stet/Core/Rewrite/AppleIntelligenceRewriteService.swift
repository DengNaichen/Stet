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

        // Order is tuned for small on-device model recency bias: generic base first,
        // Apple-specific overrides next, examples, then the highest-priority reminder
        // sits last so it has the strongest influence on the next generated tokens.
        // Keep tone neutral — aggressive DO NOT / NEVER phrasing triggers safety refusals.
        let languageLaw = """
            Output the transcript in the exact language(s) the speaker used. Never translate.
            Match punctuation to the language: full-width （，。？！） for Chinese, ASCII for English.
            """

        var reminder = """
            Reminder:
            Apply transcript cleanup when any cleanup is available.
            If the input contains filler words, repeated words, missing punctuation, missing capitalization, or obvious STT artifacts, return the cleaned version.
            Return the original only when it is already clean.
            For Chinese text, use full-width punctuation （，。？！） in Chinese spans.
            """
        if let languageCode = request.languageCode {
            reminder += "\nThe speaker's primary language is \(languageCode)."
        }

        return """
            \(base)

            \(languageLaw)

            ### Example 1 — remove filler words (Chinese):
            Input: "那个，我今天觉得天气，嗯，挺好的，我们出去走走吧。"
            Output: "我今天觉得天气挺好的，我们出去走走吧。"

            Input: "就是那个那个呃就是那个,我的意思是把那个 button 改一下。"
            Output: "我的意思是，把那个 button 改一下。"

            ### Example 2 — preserve mixed Chinese-English exactly:
            Input: "这个coreml model的performance还可以。"
            Output: "这个 CoreML model 的 performance 还可以。"

            ### Example 3 — preserve speaker's casual register and profanity:
            Input: "我靠这个bug也太离谱了，你他妈帮我看看这个 stack trace 是什么意思。"
            Output: "我靠这个bug也太离谱了，你他妈帮我看看这个 stack trace 是什么意思。"

            ### Example 4 — remove filler words (English):
            Input: "um, uh, so I think we should probably, uh, refactor this whole module."
            Output: "I think we should refactor this whole module."

            ### Example 5 — add punctuation generously in long passages (Chinese):
            Input: "我今天去了一趟超市买了一些菜然后回家做饭吃完饭之后看了一会儿电视就睡觉了第二天早上起来发现外面下雨了"
            Output: "我今天去了一趟超市，买了一些菜。然后回家做饭，吃完饭之后看了一会儿电视，就睡觉了。第二天早上起来，发现外面下雨了。"

            ### Example 6 — clean short English transcripts:
            Input: "i think this prompt engineering thing is actually pretty hard"
            Output: "I think this prompt engineering thing is actually pretty hard."

            Input: "yeah um can you maybe take a look at this stack trace"
            Output: "Yeah, can you maybe take a look at this stack trace?"

            Input: "so the model is basically not changing anything right now"
            Output: "The model is basically not changing anything right now."

            ### Example 7 — add punctuation to short Chinese:
            Input: "他现在加标点加的还是不是很积极啊能不能跟他说一声啊"
            Output: "他现在加标点加的还是不是很积极啊？能不能跟他说一声啊？"

            Input: "我知道了原来这个prompt工程其实还挺难的"
            Output: "我知道了，原来这个 prompt 工程其实还挺难的。"

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
