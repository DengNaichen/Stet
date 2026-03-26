#if os(macOS)
    import SwiftUI

    public enum MacDictationShaderTheme: String, CaseIterable, Identifiable, Hashable {
        case blossom
        case egg
        case harbor
        case cat
        case beacon
        case autumn

        public var id: String { rawValue }

        public var title: String {
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

        var palette: MacDictationShaderThemePalette {
            switch self {
            case .blossom:
                let sky = (0.5294117647058824, 0.7019607843137254, 0.8862745098039215)
                let leaf = (0.7176470588235294, 0.796078431372549, 0.3607843137254902)
                let petal = (0.9058823529411765, 0.5568627450980392, 0.5725490196078431)
                return MacDictationShaderThemePalette(
                    idle: .init(
                        a: sky,
                        b: leaf,
                        c: petal
                    ),
                    starting: .init(
                        a: sky,
                        b: leaf,
                        c: petal
                    ),
                    speaking: .init(
                        a: sky,
                        b: leaf,
                        c: petal
                    ),
                    processing: .init(
                        a: sky,
                        b: leaf,
                        c: petal
                    )
                )
            case .egg:
                let sky = (0.3686274509803921, 0.5529411764705883, 0.6549019607843137)
                let yolk = (0.8627450980392157, 0.596078431372549, 0.011764705882352941)
                let shell = (0.792156862745098, 0.792156862745098, 0.7490196078431373)
                return MacDictationShaderThemePalette(
                    idle: .init(
                        a: sky,
                        b: yolk,
                        c: shell
                    ),
                    starting: .init(
                        a: sky,
                        b: yolk,
                        c: shell
                    ),
                    speaking: .init(
                        a: shell,
                        b: sky,
                        c: yolk
                    ),
                    processing: .init(
                        a: yolk,
                        b: shell,
                        c: sky
                    )
                )
            case .harbor:
                let tide = (0.00392156862745098, 0.2980392156862745, 0.4117647058823529)
                let timber = (0.22745098039215686, 0.1450980392156863, 0.12549019607843137)
                let clay = (0.6901960784313725, 0.3686274509803922, 0.3568627450980392)
                return MacDictationShaderThemePalette(
                    idle: .init(
                        a: tide,
                        b: timber,
                        c: clay
                    ),
                    starting: .init(
                        a: tide,
                        b: timber,
                        c: clay
                    ),
                    speaking: .init(
                        a: clay,
                        b: tide,
                        c: timber
                    ),
                    processing: .init(
                        a: timber,
                        b: clay,
                        c: tide
                    )
                )
            case .cat:
                let red = (0.6352941176470588, 0.1803921568627451, 0.1803921568627451)
                let paper = (0.9333333333333333, 0.9254901960784314, 0.9294117647058824)
                let black = (0.09803921568627451, 0.09019607843137255, 0.09411764705882353)
                return MacDictationShaderThemePalette(
                    idle: .init(
                        a: red,
                        b: paper,
                        c: black
                    ),
                    starting: .init(
                        a: red,
                        b: paper,
                        c: black
                    ),
                    speaking: .init(
                        a: paper,
                        b: red,
                        c: black
                    ),
                    processing: .init(
                        a: red,
                        b: black,
                        c: paper
                    )
                )
            case .beacon:
                let teal = (0.0196078431372549, 0.20392156862745098, 0.2784313725490196)
                let blue = (0.01568627450980392, 0.3176470588235294, 0.6784313725490196)
                let gold = (0.9372549019607843, 0.6470588235294118, 0.058823529411764705)
                return MacDictationShaderThemePalette(
                    idle: .init(
                        a: gold,
                        b: blue,
                        c: teal
                    ),
                    starting: .init(
                        a: blue,
                        b: gold,
                        c: teal
                    ),
                    speaking: .init(
                        a: teal,
                        b: gold,
                        c: blue
                    ),
                    processing: .init(
                        a: gold,
                        b: teal,
                        c: blue
                    )
                )
            case .autumn:
                let yellow = (0.9921568627450981, 0.7607843137254902, 0.3058823529411765)
                let red = (0.996078431372549, 0.2980392156862745, 0.27058823529411763)
                let teal = (0.09411764705882353, 0.4666666666666667, 0.5372549019607843)
                return MacDictationShaderThemePalette(
                    idle: .init(
                        a: yellow,
                        b: red,
                        c: teal
                    ),
                    starting: .init(
                        a: yellow,
                        b: red,
                        c: teal
                    ),
                    speaking: .init(
                        a: red,
                        b: yellow,
                        c: teal
                    ),
                    processing: .init(
                        a: yellow,
                        b: teal,
                        c: red
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
        let a: (Double, Double, Double)
        let b: (Double, Double, Double)
        let c: (Double, Double, Double)
    }
#endif
