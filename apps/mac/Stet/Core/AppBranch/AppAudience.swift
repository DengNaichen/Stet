#if os(macOS)
import Foundation

enum AppAudience: String, Codable, Sendable {
    case human
    case ai

    var isAI: Bool {
        self == .ai
    }
}

enum AppAudienceResolver {
    private static let aiNameFragments: [String] = [
        "android studio",
        "androidstudio",
        "aider",
        "antigravity",
        "augment",
        "bolt",
        "chatgpt",
        "claude",
        "claude code",
        "cline",
        "clion",
        "codex",
        "codeium",
        "continue",
        "gemini",
        "copilot",
        "cursor",
        "fleet",
        "goland",
        "intellij",
        "kiro",
        "perplexity",
        "phpstorm",
        "poe",
        "pycharm",
        "replit",
        "roo code",
        "rider",
        "trae",
        "vscode",
        "vscode insiders",
        "visual studio code",
        "warp",
        "webstorm",
        "windsurf",
        "xcode",
        "zed"
    ]

    nonisolated static func resolve(
        bundleIdentifier: String,
        localizedName: String
    ) -> AppAudience {
        let normalizedBundleIdentifier = normalize(bundleIdentifier)
        let normalizedLocalizedName = normalize(localizedName)

        if aiNameFragments.contains(where: { fragment in
            normalizedBundleIdentifier.contains(fragment) || normalizedLocalizedName.contains(fragment)
        }) {
            return .ai
        }

        return .human
    }

    private nonisolated static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
#endif
