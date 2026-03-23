#if os(macOS)
import Foundation

enum MacOnboardingMode: String, Sendable {
    case apiKey
    case managed
}

enum MacOnboardingStep: Int, CaseIterable, Sendable {
    case mode = 1
    case apiKey
    case login
    case permissions
    case shortcut
    case firstSuccess
    case done

    var progressIndex: Int {
        switch self {
        case .mode:
            return 1
        case .apiKey, .login:
            return 2
        case .permissions:
            return 3
        case .shortcut:
            return 4
        case .firstSuccess:
            return 5
        case .done:
            return 6
        }
    }

    var allowsAudioCapture: Bool {
        switch self {
        case .shortcut, .firstSuccess:
            return true
        case .mode, .apiKey, .login, .permissions, .done:
            return false
        }
    }
}
#endif
