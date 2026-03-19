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
        var systemPrompt = "You rewrite dictated speech into polished text. Return only the rewritten text."

        if !preferredSpellings.isEmpty {
            systemPrompt += " Preserve the exact spelling of these names, brands, jargon, and technical terms when they appear or are clearly intended: \(preferredSpellings.joined(separator: ", "))."
        }

        return Self(
            sourceText: sourceText,
            instruction: "Rewrite the dictated text so it reads cleanly while preserving the original meaning, tone, and detail.",
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
