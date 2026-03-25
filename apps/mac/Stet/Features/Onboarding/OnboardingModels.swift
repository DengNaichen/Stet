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
        case appearance
        case done

        var progressIndex: Int {
            switch self {
            case .mode, .apiKey, .login:
                return 1
            case .permissions:
                return 2
            case .shortcut:
                return 3
            case .firstSuccess:
                return 4
            case .appearance, .done:
                return 5
            }
        }

        var allowsAudioCapture: Bool {
            switch self {
            case .shortcut, .firstSuccess:
                return true
            case .mode, .apiKey, .login, .permissions, .appearance, .done:
                return false
            }
        }
    }
#endif
