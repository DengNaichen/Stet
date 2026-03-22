#if os(macOS)
import SwiftUI

public enum MacDictationShaderTheme: String, CaseIterable, Identifiable, Hashable {
    case defaultTheme = "default"
    case midnight
    case sunset
    case forest

    public var id: String { rawValue }

    public var title: String {
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

    var palette: MacDictationShaderThemePalette {
        switch self {
        case .defaultTheme:
            return MacDictationShaderThemePalette(
                idle: .init(
                    top: (0.95, 0.96, 0.98),
                    mid: (0.86, 0.88, 0.90),
                    low: (0.72, 0.74, 0.76)
                ),
                starting: .init(
                    top: (0.62, 0.82, 0.96),
                    mid: (0.34, 0.60, 0.84),
                    low: (0.16, 0.40, 0.68)
                ),
                speaking: .init(
                    top: (0.35, 0.85, 1.00),
                    mid: (0.20, 0.65, 1.00),
                    low: (0.10, 0.45, 0.85)
                ),
                processing: .init(
                    top: (1.00, 0.80, 0.45),
                    mid: (1.00, 0.55, 0.12),
                    low: (0.85, 0.32, 0.08)
                )
            )
        case .midnight:
            return MacDictationShaderThemePalette(
                idle: .init(
                    top: (0.93, 0.95, 1.00),
                    mid: (0.78, 0.82, 0.92),
                    low: (0.56, 0.61, 0.74)
                ),
                starting: .init(
                    top: (0.73, 0.80, 1.00),
                    mid: (0.37, 0.49, 0.90),
                    low: (0.20, 0.28, 0.72)
                ),
                speaking: .init(
                    top: (0.52, 0.86, 1.00),
                    mid: (0.18, 0.63, 0.97),
                    low: (0.11, 0.38, 0.80)
                ),
                processing: .init(
                    top: (0.96, 0.76, 1.00),
                    mid: (0.74, 0.42, 0.96),
                    low: (0.52, 0.20, 0.72)
                )
            )
        case .sunset:
            return MacDictationShaderThemePalette(
                idle: .init(
                    top: (1.00, 0.96, 0.93),
                    mid: (0.94, 0.86, 0.78),
                    low: (0.82, 0.69, 0.58)
                ),
                starting: .init(
                    top: (1.00, 0.78, 0.58),
                    mid: (0.96, 0.55, 0.34),
                    low: (0.78, 0.30, 0.16)
                ),
                speaking: .init(
                    top: (1.00, 0.64, 0.52),
                    mid: (0.98, 0.40, 0.28),
                    low: (0.84, 0.21, 0.16)
                ),
                processing: .init(
                    top: (1.00, 0.88, 0.48),
                    mid: (1.00, 0.64, 0.12),
                    low: (0.86, 0.34, 0.08)
                )
            )
        case .forest:
            return MacDictationShaderThemePalette(
                idle: .init(
                    top: (0.94, 0.97, 0.92),
                    mid: (0.83, 0.88, 0.79),
                    low: (0.64, 0.73, 0.63)
                ),
                starting: .init(
                    top: (0.72, 0.92, 0.78),
                    mid: (0.34, 0.72, 0.50),
                    low: (0.16, 0.48, 0.28)
                ),
                speaking: .init(
                    top: (0.58, 0.94, 0.70),
                    mid: (0.20, 0.74, 0.46),
                    low: (0.08, 0.46, 0.24)
                ),
                processing: .init(
                    top: (0.96, 0.88, 0.50),
                    mid: (0.82, 0.58, 0.16),
                    low: (0.56, 0.30, 0.08)
                )
            )
        }
    }
}

struct MacDictationShaderThemePalette {
    let idle: MacDictationShaderThemeColorSet
    let starting: MacDictationShaderThemeColorSet
    let speaking: MacDictationShaderThemeColorSet
    let processing: MacDictationShaderThemeColorSet
}

struct MacDictationShaderThemeColorSet {
    let top: (Double, Double, Double)
    let mid: (Double, Double, Double)
    let low: (Double, Double, Double)
}
#endif
