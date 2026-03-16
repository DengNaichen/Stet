import Foundation

enum AppLoggerCategory {
    case general
    case hotkey
    case openAI
    case appBranch

    nonisolated var label: String {
        switch self {
        case .general:
            return "general"
        case .hotkey:
            return "hotkey"
        case .openAI:
            return "openai"
        case .appBranch:
            return "app-branch"
        }
    }

    nonisolated var preferenceKey: String? {
        switch self {
        case .general:
            return nil
        case .hotkey:
            return MacPreferences.hotkeyDebugLoggingEnabled
        case .openAI, .appBranch:
            return MacPreferences.openAIDebugLoggingEnabled
        }
    }
}

enum AppLogger {
    nonisolated static func info(
        _ message: @autoclosure () -> String,
        category: AppLoggerCategory = .general
    ) {
        log(level: "INFO", message(), category: category)
    }

    nonisolated static func warning(
        _ message: @autoclosure () -> String,
        category: AppLoggerCategory = .general
    ) {
        log(level: "WARN", message(), category: category)
    }

    nonisolated static func error(
        _ message: @autoclosure () -> String,
        category: AppLoggerCategory = .general
    ) {
        log(level: "ERROR", message(), category: category)
    }

    nonisolated private static func log(level: String, _ message: String, category: AppLoggerCategory) {
        guard shouldEmit(category: category) else { return }
        print("[airType][\(category.label)][\(level)] \(message)")
    }

    nonisolated static func shouldEmit(
        category: AppLoggerCategory,
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard let key = category.preferenceKey else {
            return true
        }

        return defaults.object(forKey: key) as? Bool ?? false
    }
}
