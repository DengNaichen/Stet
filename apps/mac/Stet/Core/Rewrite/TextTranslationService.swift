import Foundation

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
