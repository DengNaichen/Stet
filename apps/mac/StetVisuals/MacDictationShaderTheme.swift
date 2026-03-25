#if os(macOS)
    import SwiftUI

    public enum MacDictationShaderTheme: String, CaseIterable, Identifiable, Hashable {
        case midnight
        case sunset
        case forest
        case blossom
        case egg
        case harbor
        case cat
        case beacon
        case autumn

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .midnight:
                return "Midnight"
            case .sunset:
                return "Sunset"
            case .forest:
                return "Forest"
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

        var palette: MacDictationShaderThemePalette {
            switch self {
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
            case .blossom:
                let sky = (0.5294117647058824, 0.7019607843137254, 0.8862745098039215)
                let leaf = (0.7176470588235294, 0.796078431372549, 0.3607843137254902)
                let petal = (0.9058823529411765, 0.5568627450980392, 0.5725490196078431)
                return MacDictationShaderThemePalette(
                    idle: .init(
                        top: sky,
                        mid: leaf,
                        low: petal
                    ),
                    starting: .init(
                        top: sky,
                        mid: leaf,
                        low: petal
                    ),
                    speaking: .init(
                        top: sky,
                        mid: leaf,
                        low: petal
                    ),
                    processing: .init(
                        top: sky,
                        mid: leaf,
                        low: petal
                    )
                )
            case .egg:
                let sky = (0.3686274509803921, 0.5529411764705883, 0.6549019607843137)
                let yolk = (0.8627450980392157, 0.596078431372549, 0.011764705882352941)
                let shell = (0.792156862745098, 0.792156862745098, 0.7490196078431373)
                return MacDictationShaderThemePalette(
                    idle: .init(
                        top: sky,
                        mid: yolk,
                        low: shell
                    ),
                    starting: .init(
                        top: sky,
                        mid: yolk,
                        low: shell
                    ),
                    speaking: .init(
                        top: shell,
                        mid: sky,
                        low: yolk
                    ),
                    processing: .init(
                        top: yolk,
                        mid: shell,
                        low: sky
                    )
                )
            case .harbor:
                let tide = (0.00392156862745098, 0.2980392156862745, 0.4117647058823529)
                let timber = (0.22745098039215686, 0.1450980392156863, 0.12549019607843137)
                let clay = (0.6901960784313725, 0.3686274509803922, 0.3568627450980392)
                return MacDictationShaderThemePalette(
                    idle: .init(
                        top: tide,
                        mid: timber,
                        low: clay
                    ),
                    starting: .init(
                        top: tide,
                        mid: timber,
                        low: clay
                    ),
                    speaking: .init(
                        top: clay,
                        mid: tide,
                        low: timber
                    ),
                    processing: .init(
                        top: timber,
                        mid: clay,
                        low: tide
                    )
                )
            case .cat:
                let red = (0.6352941176470588, 0.1803921568627451, 0.1803921568627451)
                let paper = (0.9333333333333333, 0.9254901960784314, 0.9294117647058824)
                let black = (0.09803921568627451, 0.09019607843137255, 0.09411764705882353)
                return MacDictationShaderThemePalette(
                    idle: .init(
                        top: red,
                        mid: paper,
                        low: black
                    ),
                    starting: .init(
                        top: red,
                        mid: paper,
                        low: black
                    ),
                    speaking: .init(
                        top: paper,
                        mid: red,
                        low: black
                    ),
                    processing: .init(
                        top: red,
                        mid: black,
                        low: paper
                    )
                )
            case .beacon:
                let teal = (0.0196078431372549, 0.20392156862745098, 0.2784313725490196)
                let blue = (0.01568627450980392, 0.3176470588235294, 0.6784313725490196)
                let gold = (0.9372549019607843, 0.6470588235294118, 0.058823529411764705)
                return MacDictationShaderThemePalette(
                    idle: .init(
                        top: gold,
                        mid: blue,
                        low: teal
                    ),
                    starting: .init(
                        top: blue,
                        mid: gold,
                        low: teal
                    ),
                    speaking: .init(
                        top: teal,
                        mid: gold,
                        low: blue
                    ),
                    processing: .init(
                        top: gold,
                        mid: teal,
                        low: blue
                    )
                )
            case .autumn:
                let yellow = (0.9921568627450981, 0.7607843137254902, 0.3058823529411765)
                let red = (0.996078431372549, 0.2980392156862745, 0.27058823529411763)
                let teal = (0.09411764705882353, 0.4666666666666667, 0.5372549019607843)
                return MacDictationShaderThemePalette(
                    idle: .init(
                        top: yellow,
                        mid: red,
                        low: teal
                    ),
                    starting: .init(
                        top: yellow,
                        mid: red,
                        low: teal
                    ),
                    speaking: .init(
                        top: red,
                        mid: yellow,
                        low: teal
                    ),
                    processing: .init(
                        top: yellow,
                        mid: teal,
                        low: red
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
