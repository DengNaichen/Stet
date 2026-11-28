import SwiftUI

extension MobileDictationVisualTheme {
    var previewColors: [Color] {
        switch self {
        case .blossom:
            [
                Color(red: 0.53, green: 0.70, blue: 0.89),
                Color(red: 0.72, green: 0.80, blue: 0.36),
                Color(red: 0.91, green: 0.56, blue: 0.57),
            ]
        case .egg:
            [
                Color(red: 0.79, green: 0.79, blue: 0.75),
                Color(red: 0.37, green: 0.55, blue: 0.65),
                Color(red: 0.86, green: 0.60, blue: 0.01),
            ]
        case .harbor:
            [
                Color(red: 0.69, green: 0.37, blue: 0.36),
                Color(red: 0.00, green: 0.30, blue: 0.41),
                Color(red: 0.23, green: 0.15, blue: 0.13),
            ]
        case .cat:
            [
                Color(red: 0.93, green: 0.93, blue: 0.93),
                Color(red: 0.64, green: 0.18, blue: 0.18),
                Color(red: 0.10, green: 0.09, blue: 0.09),
            ]
        case .beacon:
            [
                Color(red: 0.94, green: 0.65, blue: 0.06),
                Color(red: 0.02, green: 0.32, blue: 0.68),
                Color(red: 0.02, green: 0.20, blue: 0.28),
            ]
        case .autumn:
            [
                Color(red: 0.99, green: 0.76, blue: 0.31),
                Color(red: 1.00, green: 0.30, blue: 0.27),
                Color(red: 0.09, green: 0.47, blue: 0.54),
            ]
        }
    }

    var accentColor: Color {
        previewColors.first ?? .accentColor
    }
}

struct ThemeOrbSwatch: View {
    let theme: MobileDictationVisualTheme
    var size: CGFloat = 34

    var body: some View {
        Circle()
            .fill(
                AngularGradient(
                    colors: theme.previewColors + [theme.previewColors.first ?? .accentColor],
                    center: .center
                )
            )
            .overlay(
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.white.opacity(0.45), .clear],
                            center: .topLeading,
                            startRadius: 1,
                            endRadius: size * 0.75
                        )
                    )
            )
            .overlay(
                Circle()
                    .strokeBorder(.primary.opacity(0.12), lineWidth: 0.75)
            )
            .frame(width: size, height: size)
    }
}
