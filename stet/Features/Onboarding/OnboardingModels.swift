#if os(macOS)
    import Foundation

    enum MacOnboardingMode: String, Sendable {
        case fluidAudio
        case localWhisper
    }

    enum MacOnboardingStep: Int, CaseIterable, Sendable {
        case language = 1
        case permissions
        case shortcut
        case firstSuccess
        case appearance
        case done

        var progressIndex: Int {
            switch self {
            case .language:
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
            case .language, .permissions, .appearance, .done:
                return false
            }
        }
    }
#endif
