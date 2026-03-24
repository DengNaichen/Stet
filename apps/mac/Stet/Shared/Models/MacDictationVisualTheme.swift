#if os(macOS)
    import Foundation

    enum MacDictationVisualTheme: String, CaseIterable, Identifiable, Hashable {
        case defaultTheme = "default"
        case midnight
        case sunset
        case forest

        var id: String { rawValue }

        var title: String {
            switch self {
            case .defaultTheme:
                return "Default"
            case .midnight:
                return "Midnight"
            case .sunset:
                return "Sunset"
            case .forest:
                return "Forest"
            }
        }

        static func fromStoredValue(_ rawValue: String?) -> Self {
            Self(rawValue: rawValue ?? "") ?? .defaultTheme
        }
    }
#endif
