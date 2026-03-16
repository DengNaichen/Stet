#if os(macOS)
import Foundation

enum AppBranchPromptVariable: String, CaseIterable, Sendable {
    case rawTranscription = "{{RAW_TRANSCRIPTION}}"
    case text = "{{TEXT}}"
    case selectedText = "{{SELECTED_TEXT}}"
    case targetLanguage = "{{TARGET_LANGUAGE}}"
    case appName = "{{APP_NAME}}"
    case bundleID = "{{BUNDLE_ID}}"
    case url = "{{URL}}"
}

struct AppBranchPromptInputs: Sendable {
    var rawTranscription: String?
    var text: String?
    var selectedText: String?
    var targetLanguage: TranslationTargetLanguage?
    var context: AppBranchContext

    nonisolated func value(for variable: AppBranchPromptVariable) -> String {
        switch variable {
        case .rawTranscription:
            return rawTranscription ?? text ?? selectedText ?? ""
        case .text:
            return text ?? rawTranscription ?? selectedText ?? ""
        case .selectedText:
            return selectedText ?? text ?? ""
        case .targetLanguage:
            return targetLanguage?.instructionName ?? ""
        case .appName:
            return context.appName ?? ""
        case .bundleID:
            return context.bundleID ?? ""
        case .url:
            return context.browserURL ?? ""
        }
    }
}

struct AppBranchPromptResolution: Sendable {
    let match: AppBranchMatch?
    let renderedPrompt: String?

    var matchedRuleName: String? { match?.rule.name }
    nonisolated var delivery: AppBranchPromptDelivery { match?.rule.promptDelivery ?? .systemPrompt }
}

enum AppBranchPromptResolver {
    nonisolated static func resolve(
        in rules: [AppBranchRule],
        snapshot: AppBranchContextSnapshot,
        inputs: AppBranchPromptInputs
    ) -> AppBranchPromptResolution {
        guard let match = AppBranchResolver.match(in: rules, context: snapshot.context) else {
            return AppBranchPromptResolution(match: nil, renderedPrompt: nil)
        }

        let renderedPrompt = render(
            template: match.rule.normalizedPrompt,
            inputs: inputs
        )
        let trimmedPrompt = renderedPrompt.trimmingCharacters(in: .whitespacesAndNewlines)

        return AppBranchPromptResolution(
            match: match,
            renderedPrompt: trimmedPrompt.isEmpty ? nil : trimmedPrompt
        )
    }

    nonisolated static func render(
        template: String,
        inputs: AppBranchPromptInputs
    ) -> String {
        var result = template
        for variable in AppBranchPromptVariable.allCases {
            result = result.replacingOccurrences(of: variable.rawValue, with: inputs.value(for: variable))
        }
        return result
    }
}
#endif
