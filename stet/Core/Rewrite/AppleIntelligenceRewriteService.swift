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

        var languageLaw = """
            [CRITICAL] You are an ASR post-processor. You must output in the exact same language the user spoke. DO NOT translate to English under any circumstances.
            Preserve the transcript language perfectly. Only correct typos in the original language.
            If the input mixes multiple languages, preserve the same language mix span by span.
            Absolutely NEVER translate any terminology or specific word spans.

            [ASR FIX] fix obvious speech-to-text typos and homophone errors.

            [FORMAT] Output plain text only. Do NOT use Markdown, asterisks, bolding, lists, or any other formatting.
            """
        if let languageCode = request.languageCode {
            languageLaw += " (Input Language: \(languageCode))"
        }

        return """
            \(languageLaw)

            \(base)

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
    private var cachedInstructions: String?
    private var session: LanguageModelSession?

    func prewarm(instructions: String, promptPrefix: String) {
        session(for: instructions).prewarm(promptPrefix: Prompt(promptPrefix))
    }

    func respond(instructions: String, prompt: String) async throws -> String {
        let response = try await session(for: instructions).respond(to: Prompt(prompt))
        return response.content
    }

    private func session(for instructions: String) -> LanguageModelSession {
        if let session, cachedInstructions == instructions {
            return session
        }

        let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
        let session = LanguageModelSession(model: model, instructions: instructions)
        self.session = session
        self.cachedInstructions = instructions
        return session
    }
}
