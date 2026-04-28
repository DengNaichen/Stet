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
    @Guide(description: "A brief explanation of why the rewrite was or was not performed")
    let reason: String
    @Guide(description: "The cleaned, properly punctuated transcript")
    let text: String
}

public struct AppleIntelligenceRewriteService: TextRewriteService {
    private let sessionStore = AppleIntelligenceRewriteSessionStore()

    public init() {}

    func prewarm(_ request: TextRewriteRequest) async {
        guard Self.isAvailable else { return }
        await sessionStore.prewarm(
            instructions: Self.instructions(for: request)
        )
    }

    func rewrite(_ request: TextRewriteRequest) async throws -> String {
        try await rewriteWithDiagnostic(request).text
    }

    func rewriteWithDiagnostic(_ request: TextRewriteRequest) async throws -> RewriteResult {
        guard Self.isAvailable else {
            throw AppleIntelligenceRewriteError.unavailable(Self.availabilityDescription)
        }

        let result = try await sessionStore.respondDiagnostic(
            instructions: Self.instructions(for: request),
            prompt: Self.prompt(for: request)
        )
        return result
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
        let isChinese = request.languageCode?.lowercased().hasPrefix("zh") == true

        let cleanupPolicy: String
        if isChinese {
            cleanupPolicy = """
                1. VERBAL SCAFFOLDING PURGE: Every single "那个", "这个", "就是", "然后", "嗯", "呃", "啊" and hesitation markers (like "……") MUST be deleted. Do not be "faithful" to these stumbling marks.
                2. SELF-CORRECTION RESOLUTION: When a speaker corrects themselves (e.g., "三点，不对，四点"), you only output the final intended meaning ("四点").
                """
        } else {
            cleanupPolicy = """
                1. ENGLISH FILLER PURGE: Delete filler-only words and phrases such as "um", "uh", filler "like", "you know", "I mean", and discourse-only "so".
                2. ENGLISH SELF-CORRECTION RESOLUTION: Treat "no", "wait no", "sorry", "actually", and "or actually" as correction markers when they replace an earlier object, name, date, number, file, target, phrase, or clause. Remove the earlier corrected span entirely and keep the later replacement span.
                3. ENGLISH INTENT PRESERVATION: Keep the speaker's intent and sentence type. Do not turn "I want to..." into a command unless the transcript is clearly addressed as a direct command.
                4. ENGLISH GRAMMAR PRESERVATION: Preserve surrounding action words and prepositions when applying a correction. If a correction changes "into A" to "into B", output "into B", not "into A, B".
                5. ENGLISH CORRECTION SPAN RULE: Around a correction marker, compare the phrase immediately before the marker with the phrase immediately after it. If both phrases fill the same role, delete the earlier phrase and splice the later phrase into the sentence with one copy of the shared preposition or verb.
                """
        }

        var reminder = """
            You are a professional Transcript Purge Engine. Your mission is to transform colloquial, messy speech-to-text transcripts into clean, professional, and concise written text.

            CRITICAL RULES:
            \(cleanupPolicy)
            6. WRITTEN STYLE: The output must sound like it was written by a professional editor.
            7. ABSOLUTE LANGUAGE LOCK: Never translate any word, phrase, clause, sentence, or language span. Keep every span in the exact language the speaker used, in the same order. Chinese spans must remain Chinese, English spans must remain English, and mixed-language text must remain mixed-language text. Do not normalize mixed-language text into one language. Do not replace a word with its translation even if the translation sounds more natural.
            8. PROPER PUNCTUATION: The output must be properly punctuated. Add periods, commas, and question marks as appropriate to ensure the text reads like a professional document.
            """

        if let languageCode = request.languageCode {
            reminder += "\nThe speaker's primary language is \(languageCode)."
        }

        if !request.preferredSpellings.isEmpty {
            reminder += """

                Personal dictionary entries are canonical recovery targets: \(request.preferredSpellings.joined(separator: ", ")).
                If the transcript contains a garbled, split, homophone, near-sound, differently capitalized, or partially translated version that clearly refers to a dictionary entry, replace it with the exact dictionary entry.
                Preserve dictionary entries exactly as written, including capitalization, spacing, and punctuation. Do not add a dictionary entry when there is no nearby spoken cue for it.
                """
        }

        let examples = loadExamples(for: request.languageCode) ?? ""

        return """
            \(reminder)

            Instruction: You must output a JSON object with two fields in this EXACT order:
            1. "reason": A brief explanation of which fillers or errors you identified.
            2. "text": The final cleaned transcript.

            \(examples)

            ### Task:
            Now, process the following input and provide the JSON output.
            """
    }

    private nonisolated static func loadExamples(for languageCode: String?) -> String? {
        let suffix = languageCode?.lowercased().hasPrefix("zh") == true ? "zh-Hans" : "en"
        let resourceName = "Rewrite_\(suffix)"

        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "txt", subdirectory: "Prompts"),
            let content = try? String(contentsOf: url, encoding: .utf8)
        else {
            return nil
        }
        return content
    }

    private nonisolated static func promptPrefix() -> String {
        let prefix = """
            Instruction:
            Clean the following raw transcription according to your instructions.

            """

        return prefix + "Text:\n"
    }

    private nonisolated static func prompt(for request: TextRewriteRequest) -> String {
        let prefix = promptPrefix()
        return prefix + request.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private actor AppleIntelligenceRewriteSessionStore {
    private var activeSession: LanguageModelSession?

    func prewarm(instructions: String) {
        let session = Self.makeSession(instructions: instructions)
        self.activeSession = session
    }

    func respond(instructions: String, prompt: String) async throws -> String {
        try await respondDiagnostic(instructions: instructions, prompt: prompt).text
    }

    func respondDiagnostic(instructions: String, prompt: String) async throws -> RewriteResult {
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

        print("  [AI Reason]: \(response.content.reason)")
        return response.content
    }

    private static func makeSession(instructions: String) -> LanguageModelSession {
        let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
        return LanguageModelSession(model: model, instructions: instructions)
    }
}
