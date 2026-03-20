import Foundation

struct TextRewriteRequest: Sendable, Equatable {
    var sourceText: String
    var instruction: String
    var systemPrompt: String?
    var additionalUserContext: String?
    var model: String?

    nonisolated static func cleanup(
        _ sourceText: String,
        preferredSpellings: [String] = [],
        additionalUserContext: String? = nil
    ) -> Self {
        var systemPrompt = """
            You are a conservative transcript editor.

            Your job is to clean raw speech-to-text transcripts with minimal edits.

            Rules:
            1. You must add punctuation and capitalization throughout the transcript.
            2. You must correct obvious speech-to-text errors when the intended meaning is clear from context.
            3. Remove filler words like "um" and "uh" and obvious transcription noise.
            4. Do not rewrite, summarize, paraphrase, or translate.
            5. Keep meaningful repetition, hesitation, and self-correction.
            6. If a correction is uncertain, keep the original wording.

            Output only the cleaned transcript.
        """

        if !preferredSpellings.isEmpty {
            systemPrompt += "\n\nPreserve the exact spelling of these names, brands, jargon, and technical terms when they appear or are clearly intended: \(preferredSpellings.joined(separator: ", "))."
        }

        return Self(
            sourceText: sourceText,
            instruction: "Clean the following raw transcription according to your instructions.",
            systemPrompt: systemPrompt,
            additionalUserContext: additionalUserContext,
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
