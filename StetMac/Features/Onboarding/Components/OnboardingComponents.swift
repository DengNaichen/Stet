#if os(macOS)
    import AppKit
    import SwiftUI

    // MARK: - Extensions

    extension Color {
        init(hex: String) {
            let hexString = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            var value: UInt64 = 0
            Scanner(string: hexString).scanHexInt64(&value)

            let r, g, b, a: Double
            switch hexString.count {
            case 6:
                r = Double((value >> 16) & 0xFF) / 255
                g = Double((value >> 8) & 0xFF) / 255
                b = Double(value & 0xFF) / 255
                a = 1
            case 8:
                r = Double((value >> 24) & 0xFF) / 255
                g = Double((value >> 16) & 0xFF) / 255
                b = Double((value >> 8) & 0xFF) / 255
                a = Double(value & 0xFF) / 255
            default:
                r = 0
                g = 0
                b = 0
                a = 1
            }

            self.init(red: r, green: g, blue: b, opacity: a)
        }
    }

    // MARK: - Metrics & Palette

    enum OnboardingMetrics {
        static let windowWidth: CGFloat = 600
        static let windowHeight: CGFloat = 556
        static let headerHeight: CGFloat = 46
        static let footerHeight: CGFloat = 62
        static let contentHorizontalPadding: CGFloat = 36
        static let footerHorizontalPadding: CGFloat = 28
        static let buttonHeight: CGFloat = 34
        static let compactButtonHeight: CGFloat = 28
        static let buttonCornerRadius: CGFloat = 8
        static let cardCornerRadius: CGFloat = 11
    }

    enum OnboardingPalette {
        static let primaryButtonBackground = Color(
            nsColor: MacUI.Palette.adaptive(
                light: NSColor(srgbRed: 24 / 255, green: 25 / 255, blue: 28 / 255, alpha: 1),
                dark: NSColor(srgbRed: 242 / 255, green: 243 / 255, blue: 245 / 255, alpha: 1)
            )
        )

        static let primaryButtonHover = Color(
            nsColor: MacUI.Palette.adaptive(
                light: NSColor(srgbRed: 44 / 255, green: 46 / 255, blue: 51 / 255, alpha: 1),
                dark: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
            )
        )

        static let primaryButtonForeground = Color(
            nsColor: MacUI.Palette.adaptive(
                light: NSColor.white,
                dark: NSColor(srgbRed: 20 / 255, green: 21 / 255, blue: 24 / 255, alpha: 1)
            )
        )

        static let accentSoft = MacUI.LinearBrand.accent.opacity(0.12)
        static let accentBorder = MacUI.LinearBrand.accent.opacity(0.32)

        static let keycapTop = Color(
            nsColor: MacUI.Palette.adaptive(
                light: NSColor.white,
                dark: NSColor(srgbRed: 45 / 255, green: 47 / 255, blue: 54 / 255, alpha: 1)
            )
        )

        static let keycapBottom = Color(
            nsColor: MacUI.Palette.adaptive(
                light: NSColor(srgbRed: 243 / 255, green: 244 / 255, blue: 246 / 255, alpha: 1),
                dark: NSColor(srgbRed: 35 / 255, green: 37 / 255, blue: 43 / 255, alpha: 1)
            )
        )

        static let capsuleSurface = Color(
            nsColor: MacUI.Palette.adaptive(
                light: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.90),
                dark: NSColor(srgbRed: 34 / 255, green: 36 / 255, blue: 42 / 255, alpha: 0.90)
            )
        )

        static func themeSwatches(for theme: MacDictationVisualTheme) -> [Color] {
            switch theme {
            case .watercolor:
                return [Color(hex: "#D6F5FA"), Color(hex: "#FEFFFD"), Color(hex: "#06A1F7")]
            case .blossom:
                return [Color(hex: "#87B3E2"), Color(hex: "#B7CB5C"), Color(hex: "#E78E92")]
            case .egg:
                return [Color(hex: "#5E8DA7"), Color(hex: "#DC9803"), Color(hex: "#CACABF")]
            case .harbor:
                return [Color(hex: "#014C69"), Color(hex: "#3A2520"), Color(hex: "#B05E5B")]
            case .cat:
                return [Color(hex: "#A22E2E"), Color(hex: "#EEECED"), Color(hex: "#191718")]
            case .beacon:
                return [Color(hex: "#EFA50F"), Color(hex: "#0451AD"), Color(hex: "#053447")]
            case .autumn:
                return [Color(hex: "#FDC24E"), Color(hex: "#FE4C45"), Color(hex: "#187789")]
            }
        }

        static func shortTitle(for theme: MacDictationVisualTheme) -> LocalizedStringKey {
            switch theme {
            case .watercolor:
                return "Watercolor"
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
    }

    // MARK: - Step Shell Pieces

    struct OnboardingStepHeader: View {
        let eyebrow: LocalizedStringKey
        let title: LocalizedStringKey
        let subtitle: LocalizedStringKey

        var body: some View {
            VStack(alignment: .leading, spacing: 5) {
                Text(eyebrow)
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.4)
                    .textCase(.uppercase)
                    .foregroundStyle(MacUI.LinearBrand.accent)

                Text(title)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(MacUI.Foreground.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(MacUI.Foreground.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    struct OnboardingFooterBar<Leading: View, Trailing: View>: View {
        @ViewBuilder let leading: () -> Leading
        @ViewBuilder let trailing: () -> Trailing

        var body: some View {
            VStack(spacing: 0) {
                LinearHairlineDivider()

                HStack(spacing: 12) {
                    leading()
                    Spacer(minLength: 8)
                    HStack(spacing: 8) {
                        trailing()
                    }
                }
                .padding(.horizontal, OnboardingMetrics.footerHorizontalPadding)
                .frame(height: OnboardingMetrics.footerHeight)
                .background(MacUI.LinearSurfaces.detailCanvas)
            }
        }
    }

    // MARK: - macOS Native-Scale Buttons

    struct OnboardingPrimaryButton: View {
        private let label: Text
        var isEnabled: Bool = true
        var isLoading: Bool = false
        let action: () -> Void

        @State private var isHovering = false

        init(
            _ title: LocalizedStringKey,
            isEnabled: Bool = true,
            isLoading: Bool = false,
            action: @escaping () -> Void
        ) {
            self.label = Text(title)
            self.isEnabled = isEnabled
            self.isLoading = isLoading
            self.action = action
        }

        init(
            verbatim title: String,
            isEnabled: Bool = true,
            isLoading: Bool = false,
            action: @escaping () -> Void
        ) {
            self.label = Text(verbatim: title)
            self.isEnabled = isEnabled
            self.isLoading = isLoading
            self.action = action
        }

        var body: some View {
            Button(action: action) {
                HStack(spacing: 6) {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.75)
                    }

                    label
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(OnboardingPalette.primaryButtonForeground)
                .padding(.horizontal, 14)
                .frame(height: OnboardingMetrics.buttonHeight)
                .background(
                    RoundedRectangle(cornerRadius: OnboardingMetrics.buttonCornerRadius, style: .continuous)
                        .fill(
                            isHovering && isEnabled
                                ? OnboardingPalette.primaryButtonHover
                                : OnboardingPalette.primaryButtonBackground
                        )
                )
                .shadow(color: Color.black.opacity(0.10), radius: 2, x: 0, y: 1)
                .contentShape(
                    RoundedRectangle(cornerRadius: OnboardingMetrics.buttonCornerRadius, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled || isLoading)
            .opacity(isEnabled && !isLoading ? 1 : 0.42)
            .onHover { isHovering = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovering)
        }
    }

    struct OnboardingSecondaryButton: View {
        private let label: Text
        var isCompact: Bool = false
        var isEnabled: Bool = true
        let action: () -> Void

        @State private var isHovering = false

        init(
            _ title: LocalizedStringKey,
            isCompact: Bool = false,
            isEnabled: Bool = true,
            action: @escaping () -> Void
        ) {
            self.label = Text(title)
            self.isCompact = isCompact
            self.isEnabled = isEnabled
            self.action = action
        }

        init(
            verbatim title: String,
            isCompact: Bool = false,
            isEnabled: Bool = true,
            action: @escaping () -> Void
        ) {
            self.label = Text(verbatim: title)
            self.isCompact = isCompact
            self.isEnabled = isEnabled
            self.action = action
        }

        var body: some View {
            let cornerRadius: CGFloat = isCompact ? 7 : OnboardingMetrics.buttonCornerRadius
            let height: CGFloat = isCompact ? OnboardingMetrics.compactButtonHeight : OnboardingMetrics.buttonHeight

            Button(action: action) {
                label
                    .font(.system(size: isCompact ? 12 : 13, weight: .medium))
                    .foregroundStyle(MacUI.Foreground.primary)
                    .padding(.horizontal, isCompact ? 11 : 14)
                    .frame(height: height)
                    .background(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(isHovering ? MacUI.LinearSurfaces.elevated : MacUI.LinearSurfaces.card)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(MacUI.LinearSurfaces.hairlineStrong, lineWidth: 1)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
            .opacity(isEnabled ? 1 : 0.45)
            .onHover { isHovering = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovering)
        }
    }

    struct OnboardingBackButton: View {
        let action: () -> Void
        @State private var isHovering = false

        var body: some View {
            Button(action: action) {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Back")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(isHovering ? MacUI.Foreground.primary : MacUI.Foreground.secondaryColor)
                .padding(.horizontal, 10)
                .frame(height: OnboardingMetrics.buttonHeight)
                .background(
                    RoundedRectangle(cornerRadius: OnboardingMetrics.buttonCornerRadius, style: .continuous)
                        .fill(isHovering ? MacUI.LinearSurfaces.elevated : .clear)
                )
                .contentShape(
                    RoundedRectangle(cornerRadius: OnboardingMetrics.buttonCornerRadius, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovering)
        }
    }

    struct OnboardingStatusPill: View {
        private let label: Text
        var systemImage: String = "checkmark"
        var tint: Color = MacUI.Foreground.success

        init(_ title: LocalizedStringKey, systemImage: String = "checkmark", tint: Color = MacUI.Foreground.success) {
            self.label = Text(title)
            self.systemImage = systemImage
            self.tint = tint
        }

        init(verbatim title: String, systemImage: String = "checkmark", tint: Color = MacUI.Foreground.success) {
            self.label = Text(verbatim: title)
            self.systemImage = systemImage
            self.tint = tint
        }

        var body: some View {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 10.5, weight: .bold))
                label
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.11))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(tint.opacity(0.25), lineWidth: 1)
            )
        }
    }

    struct OnboardingFeaturePill: View {
        let title: LocalizedStringKey
        let systemImage: String

        var body: some View {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(MacUI.LinearBrand.accent)

                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(MacUI.Foreground.secondary)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(MacUI.LinearSurfaces.card)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(MacUI.LinearSurfaces.hairline, lineWidth: 1)
            )
        }
    }
#endif
