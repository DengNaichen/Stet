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
        var reminder = """
            You are a professional Transcript Purge Engine. Your mission is to transform colloquial, messy speech-to-text transcripts into clean, professional, and concise written text.

            CRITICAL RULES:
            1. VERBAL SCAFFOLDING PURGE: Every single "那个", "这个", "就是", "然后", "嗯", "呃", "啊" and hesitation markers (like repetitions or ellipses "……") MUST be deleted. Do not be "faithful" to these stumbling marks.
            2. SELF-CORRECTION RESOLUTION: When a speaker corrects themselves (e.g., "三点，不对，四点"), you only output the final intended meaning ("四点").
            3. WRITTEN STYLE: The output must sound like it was written by a professional editor.
            4. LANGUAGE LOCK: Keep each span in the same language the speaker used. Do not translate, do not normalize mixed-language text into one language, and do not introduce English terms into a Chinese span or Chinese terms into an English span. Only restore a cross-language technical term when the original recognition clearly intended that exact term.
            5. PROPER PUNCTUATION: The output must be properly punctuated. Add periods, commas, and question marks as appropriate to ensure the text reads like a professional document.
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

        return """
            \(reminder)

            Instruction: You must output a JSON object with two fields in this EXACT order:
            1. "reason": A brief explanation of which fillers or errors you identified.
            2. "text": The final cleaned transcript.

            ### Example 1 (Aggressive Cleanup):
            Input: "那个就是，你把那个按钮，嗯，改成蓝色吧。"
            Output: { "reason": "Removed verbal pauses '那个就是', '那个', '嗯'.", "text": "把按钮改成蓝色吧。" }

            ### Example 2 (Long Opening):
            Input: "反正就是，怎么说呢，那个，这个项目其实挺难搞的。"
            Output: { "reason": "Purged long opening scaffolding.", "text": "这个项目其实挺难搞的。" }

            ### Example 3 (Mixed Technical Terms):
            Input: "就是那个，你把那个 JSON 传到那个 Server 端，嗯，做个 validation。"
            Output: { "reason": "Cleaned fillers, preserved technical terms.", "text": "把 JSON 传到 Server 端做 validation。" }

            ### Example 4 (Logic Resolution):
            Input: "我们明天去北京，啊不对，我们明天去上海吧。"
            Output: { "reason": "Resolved self-correction from Beijing to Shanghai.", "text": "我们明天去上海吧。" }

            ### Example 5 (Hesitation & Ellipses Purge):
            Input: "那个……那个……我就是想问一下，那个，工资发了吗？"
            Output: { "reason": "Purged hesitation marks (ellipses and repetitions) to create a clean question.", "text": "我就是想问一下，工资发了吗？" }

            ### Example 6 (Clean Spoken Structure):
            Input: "嗯我觉得这个方案可以先这样定下来如果后面数据不对我们再调整"
            Output: { "reason": "split the run-on sentence into clear written structure.", "text": "这个方案可以先这样定下来。如果后面数据不对，我们再调整。" }

            ### Task:
            Now, process the following input and provide the JSON output.
            """
    }

    private nonisolated static func promptPrefix(additionalContext: String?) -> String {
        var prefix = """
            Instruction:
            Clean the following raw transcription according to your instructions.

            """

        return prefix + "Text:\n"
    }

    private nonisolated static func prompt(for request: TextRewriteRequest) -> String {
        let prefix = promptPrefix(additionalContext: nil)
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
