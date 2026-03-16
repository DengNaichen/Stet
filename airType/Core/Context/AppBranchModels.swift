#if os(macOS)
import Foundation

enum AppBranchPromptDelivery: String, CaseIterable, Identifiable, Codable, Sendable {
    case systemPrompt
    case userMessage

    nonisolated var id: String { rawValue }

    nonisolated var title: String {
        switch self {
        case .systemPrompt:
            return "System Prompt"
        case .userMessage:
            return "User Message"
        }
    }

    nonisolated var detail: String {
        switch self {
        case .systemPrompt:
            return "Inject the rendered App Branch prompt into the system instruction."
        case .userMessage:
            return "Inject the rendered App Branch prompt into the user message for the current action."
        }
    }
}

struct AppBranchAppTarget: Identifiable, Codable, Hashable, Sendable {
    var bundleID: String
    var displayName: String

    nonisolated var id: String { bundleID }
}

struct AppBranchRule: Identifiable, Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case prompt
        case promptDelivery
        case appTargets
        case urlPatterns
        case isEnabled
    }

    var id: UUID
    var name: String
    var prompt: String
    var promptDelivery: AppBranchPromptDelivery
    var appTargets: [AppBranchAppTarget]
    var urlPatterns: [String]
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        name: String,
        prompt: String,
        promptDelivery: AppBranchPromptDelivery = .userMessage,
        appTargets: [AppBranchAppTarget] = [],
        urlPatterns: [String] = [],
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.prompt = prompt
        self.promptDelivery = promptDelivery
        self.appTargets = appTargets
        self.urlPatterns = urlPatterns.map(Self.canonicalizeURLPattern)
        self.isEnabled = isEnabled
    }

    nonisolated var normalizedPrompt: String {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated var bundleIdentifiers: [String] {
        appTargets.map(\.bundleID)
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        prompt = try container.decode(String.self, forKey: .prompt)
        promptDelivery = try container.decodeIfPresent(AppBranchPromptDelivery.self, forKey: .promptDelivery) ?? .userMessage
        appTargets = try container.decodeIfPresent([AppBranchAppTarget].self, forKey: .appTargets) ?? []
        urlPatterns = (try container.decodeIfPresent([String].self, forKey: .urlPatterns) ?? []).map(Self.canonicalizeURLPattern)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(prompt, forKey: .prompt)
        try container.encode(promptDelivery, forKey: .promptDelivery)
        try container.encode(appTargets, forKey: .appTargets)
        try container.encode(urlPatterns, forKey: .urlPatterns)
        try container.encode(isEnabled, forKey: .isEnabled)
    }

    nonisolated func matches(context: AppBranchContext) -> Bool {
        guard isEnabled else { return false }

        let normalizedURL = AppBranchContext.normalizedURL(context.browserURL)

        if let normalizedURL {
            for pattern in urlPatterns where Self.urlMatches(pattern: pattern, candidate: normalizedURL) {
                return true
            }
        }

        guard let bundleID = context.bundleID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !bundleID.isEmpty else {
            return false
        }

        return bundleIdentifiers.contains(bundleID)
    }

    nonisolated static func canonicalizeURLPattern(_ rawValue: String) -> String {
        var normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if normalized.hasPrefix("https://") {
            normalized.removeFirst("https://".count)
        } else if normalized.hasPrefix("http://") {
            normalized.removeFirst("http://".count)
        }

        if normalized.hasSuffix("/") {
            normalized.append("*")
        } else if !normalized.contains("/") {
            normalized.append("/*")
        }

        return normalized
    }

    nonisolated static func urlMatches(pattern: String, candidate: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: canonicalizeURLPattern(pattern))
            .replacingOccurrences(of: "\\*", with: ".*")
        let regexPattern = "^\(escaped)$"
        return candidate.range(of: regexPattern, options: .regularExpression) != nil
    }
}

struct AppBranchContext: Sendable {
    var bundleID: String?
    var appName: String?
    var browserURL: String?

    nonisolated static func normalizedURL(_ rawValue: String?) -> String? {
        guard var normalized = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !normalized.isEmpty else {
            return nil
        }

        if normalized.hasPrefix("https://") {
            normalized.removeFirst("https://".count)
        } else if normalized.hasPrefix("http://") {
            normalized.removeFirst("http://".count)
        }

        return normalized
    }
}

struct AppBranchContextSnapshot: Sendable {
    var context: AppBranchContext
    var capturedAt: Date
}

struct AppBranchMatch: Sendable {
    let rule: AppBranchRule
    let matchedURLPattern: String?
}

enum AppBranchResolver {
    nonisolated static func match(
        in rules: [AppBranchRule],
        context: AppBranchContext
    ) -> AppBranchMatch? {
        let normalizedURL = AppBranchContext.normalizedURL(context.browserURL)

        if let normalizedURL {
            for rule in rules where rule.isEnabled {
                for pattern in rule.urlPatterns where AppBranchRule.urlMatches(pattern: pattern, candidate: normalizedURL) {
                    if !rule.normalizedPrompt.isEmpty {
                        return AppBranchMatch(rule: rule, matchedURLPattern: pattern)
                    }
                }
            }
        }

        guard let bundleID = context.bundleID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !bundleID.isEmpty else {
            return nil
        }

        for rule in rules where rule.isEnabled {
            if rule.bundleIdentifiers.contains(bundleID), !rule.normalizedPrompt.isEmpty {
                return AppBranchMatch(rule: rule, matchedURLPattern: nil)
            }
        }

        return nil
    }

    nonisolated static func matchedRule(
        in rules: [AppBranchRule],
        context: AppBranchContext
    ) -> AppBranchRule? {
        match(in: rules, context: context)?.rule
    }
}
#endif
