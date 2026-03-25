#if os(macOS)
    import Foundation

    enum MacOnboardingMode: String, Sendable {
        case apiKey
        case managed
    }

    enum MacOnboardingStep: Int, CaseIterable, Sendable {
        case apiKey = 1
        case login
        case permissions
        case shortcut
        case firstSuccess
        case appearance
        case done

        var progressIndex: Int {
            switch self {
            case .apiKey, .login:
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
            case .apiKey, .login, .permissions, .appearance, .done:
                return false
            }
        }
    }
#endif
