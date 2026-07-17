#if os(macOS)
    import SwiftUI

    struct OAuthSignInButtonGroup: View {
        var buttonWidth: CGFloat? = 316
        var isEnabled: Bool = true
        let appleAction: () -> Void
        let googleAction: () -> Void
        let githubAction: () -> Void

        var body: some View {
            VStack(spacing: 10) {
                providerButton(AppleSignInButton(action: appleAction))
                providerButton(GoogleSignInButton(action: googleAction))
                providerButton(GitHubSignInButton(action: githubAction))
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .disabled(!isEnabled)
        }

        @ViewBuilder
        private func providerButton<Content: View>(_ content: Content) -> some View {
            if let buttonWidth {
                content.frame(width: buttonWidth)
            } else {
                content
            }
        }
    }

    private struct OAuthButtonLabel<Icon: View>: View {
        let title: String
        var contentWidth: CGFloat = 176
        var iconSlotWidth: CGFloat = 20
        @ViewBuilder let icon: () -> Icon

        var body: some View {
            HStack {
                Spacer(minLength: 0)

                HStack(spacing: 10) {
                    icon()
                        .frame(width: iconSlotWidth, height: 20, alignment: .center)

                    Text(title)
                        .font(.system(size: 14, weight: .medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(width: contentWidth, alignment: .leading)

                Spacer(minLength: 0)
            }
        }
    }

    private struct OAuthProviderButtonChrome<Label: View>: View {
        let action: () -> Void
        let textColor: Color?
        let backgroundColor: Color
        let borderColor: Color
        var borderWidth: CGFloat = 1
        @ViewBuilder let label: () -> Label

        @State private var isHovering = false
        @State private var isPressed = false

        private let cornerRadius: CGFloat = 16

        var body: some View {
            Button(action: action) {
                label()
                    .foregroundStyle(textColor ?? .primary)
                    .frame(height: 48)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(resolvedBackgroundColor)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(borderColor, lineWidth: borderWidth)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in isPressed = true }
                    .onEnded { _ in isPressed = false }
            )
        }

        private var resolvedBackgroundColor: Color {
            if isPressed {
                return backgroundColor.opacity(0.92)
            }
            if isHovering {
                return backgroundColor.opacity(0.97)
            }
            return backgroundColor
        }
    }

    /// Google Sign-In button following official branding guidelines
    /// Reference: https://developers.google.com/identity/branding-guidelines
    struct GoogleSignInButton: View {
        let action: () -> Void
        @Environment(\.colorScheme) private var colorScheme

        var body: some View {
            OAuthProviderButtonChrome(
                action: action,
                textColor: nil,
                backgroundColor: backgroundColor,
                borderColor: borderColor
            ) {
                OAuthButtonLabel(title: "Sign in with Google") {
                    googleLogo
                }
            }
        }

        private var googleLogo: some View {
            Image("googleSignInMark")
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
        }

        private var backgroundColor: Color {
            switch colorScheme {
            case .light:
                return Color.white
            case .dark:
                return Color(red: 0.075, green: 0.075, blue: 0.078)
            @unknown default:
                return Color.white
            }
        }

        private var borderColor: Color {
            switch colorScheme {
            case .light:
                return Color.black.opacity(0.2)
            case .dark:
                return Color.white.opacity(0.2)
            @unknown default:
                return Color.gray
            }
        }
    }

    /// Apple Sign-In button following Apple Human Interface Guidelines
    /// Reference: https://developer.apple.com/design/human-interface-guidelines/sign-in-with-apple
    struct AppleSignInButton: View {
        let action: () -> Void
        @Environment(\.colorScheme) private var colorScheme

        var body: some View {
            OAuthProviderButtonChrome(
                action: action,
                textColor: textColor,
                backgroundColor: backgroundColor,
                borderColor: borderColor,
                borderWidth: 1
            ) {
                OAuthButtonLabel(title: "Sign in with Apple") {
                    appleLogo
                }
            }
        }

        private var appleLogo: some View {
            Image(systemName: "apple.logo")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(logoColor)
        }

        private var backgroundColor: Color {
            switch colorScheme {
            case .light:
                return Color.white
            case .dark:
                return Color.black
            @unknown default:
                return Color.white
            }
        }

        private var textColor: Color {
            switch colorScheme {
            case .light:
                return Color.black
            case .dark:
                return Color.white
            @unknown default:
                return Color.black
            }
        }

        private var logoColor: Color {
            switch colorScheme {
            case .light:
                return Color.black
            case .dark:
                return Color.white
            @unknown default:
                return Color.black
            }
        }

        private var borderColor: Color {
            switch colorScheme {
            case .light:
                return Color.black.opacity(0.2)
            case .dark:
                return Color.white.opacity(0.2)
            @unknown default:
                return Color.gray
            }
        }

        private var borderWidth: CGFloat {
            1
        }
    }

    /// GitHub Sign-In button following GitHub branding guidelines
    /// Reference: https://github.com/logos
    struct GitHubSignInButton: View {
        let action: () -> Void
        @Environment(\.colorScheme) private var colorScheme

        var body: some View {
            OAuthProviderButtonChrome(
                action: action,
                textColor: textColor,
                backgroundColor: backgroundColor,
                borderColor: borderColor
            ) {
                OAuthButtonLabel(title: "Sign in with GitHub") {
                    githubLogo
                }
            }
        }

        private var githubLogo: some View {
            Image("githubSignInMark")
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
        }

        private var backgroundColor: Color {
            switch colorScheme {
            case .light:
                return Color.white
            case .dark:
                return Color(red: 0.075, green: 0.075, blue: 0.078)
            @unknown default:
                return Color.white
            }
        }

        private var textColor: Color {
            switch colorScheme {
            case .light:
                return Color.black
            case .dark:
                return Color.white
            @unknown default:
                return Color.black
            }
        }

        private var borderColor: Color {
            switch colorScheme {
            case .light:
                return Color.black.opacity(0.2)
            case .dark:
                return Color.white.opacity(0.2)
            @unknown default:
                return Color.gray
            }
        }
    }
#endif
