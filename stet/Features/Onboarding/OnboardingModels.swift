#if os(macOS)
    import Foundation

    enum MacOnboardingMode: String, Sendable {
        case apiKey
    }

    enum MacOnboardingStep: Int, CaseIterable, Sendable {
        case download = 1
        case apiKey
        case permissions
        case shortcut
        case firstSuccess
        case appearance
        case done

        var progressIndex: Int {
            switch self {
            case .download:
                return 1
            case .apiKey:
                return 2
            case .permissions:
                return 3
            case .shortcut:
                return 4
            case .firstSuccess:
                return 5
            case .appearance, .done:
                return 6
            }
        }

        var allowsAudioCapture: Bool {
            switch self {
            case .shortcut, .firstSuccess:
                return true
            case .download, .apiKey, .permissions, .appearance, .done:
                return false
            }
        }
    }
#endif
