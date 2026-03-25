#if os(macOS)
    import Foundation

    enum MacDictationVisualTheme: String, CaseIterable, Identifiable, Hashable {
        case blossom
        case egg
        case harbor
        case cat
        case beacon
        case autumn

        var id: String { rawValue }

        var title: String {
            switch self {
            case .blossom:
                return "Blossom"
            case .egg:
                return "Egg"
            case .harbor:
                return "Harbor"
            case .cat:
                return "Cat"
            case .beacon:
                return "Beacon"
            case .autumn:
                return "Autumn"
            }
        }

        static func fromStoredValue(_ rawValue: String?) -> Self {
            Self(rawValue: rawValue ?? "") ?? .egg
        }
    }
#endif
