#if os(macOS)
import Foundation

enum MacOnboardingMode: String, Sendable {
    case apiKey
    case managed
}

enum MacOnboardingStep: Int, CaseIterable, Sendable {
    case welcome = 1
    case mode
    case apiKey
    case login
    case permissions
    case shortcut
    case firstSuccess
    case done

    var progressIndex: Int {
        switch self {
        case .welcome:
            return 1
        case .mode:
            return 2
        case .apiKey, .login:
            return 3
        case .permissions:
            return 4
        case .shortcut:
            return 5
        case .firstSuccess:
            return 6
        case .done:
            return 7
        }
    }

    var allowsAudioCapture: Bool {
        switch self {
        case .shortcut, .firstSuccess:
            return true
        case .welcome, .mode, .apiKey, .login, .permissions, .done:
            return false
        }
    }
}
#endif
