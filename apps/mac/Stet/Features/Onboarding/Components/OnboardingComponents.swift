#if os(macOS)
    import Foundation
    import Combine
    import ApplicationServices
    import SwiftUI

    // MARK: - Extensions

    extension Text {
        /// Apply a custom font with a fallback to system font
        func fallbackFont(_ fallback: Font) -> Text {
            // SwiftUI will automatically fall back to system font if custom font is not available
            return self
        }
    }

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

    // MARK: - Shared Surfaces

    struct OnboardingGlassCard<Content: View>: View {
        var cornerRadius: CGFloat = 24
        var fillOpacity: Double = 0.10
        var strokeOpacity: Double = 0.16
        var shadowOpacity: Double = 0.12

        @ViewBuilder let content: () -> Content

        var body: some View {
            content()
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(fillOpacity))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(strokeOpacity), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(shadowOpacity), radius: 18, x: 0, y: 10)
        }
    }

    struct OnboardingPill: View {
        let text: String
        var systemImage: String? = nil
        var tint: Color = .accentColor

        var body: some View {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.caption2.weight(.semibold))
                }

                Text(text)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.10))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(tint.opacity(0.22), lineWidth: 1)
            )
        }
    }

    struct OnboardingMetricCard: View {
        let title: String
        let value: String
        let systemImage: String
        var tint: Color = .accentColor

        var body: some View {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 22, height: 22)
                    .background(
                        Circle()
                            .fill(tint.opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(value)
                        .font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
        }
    }

    struct OnboardingStageArtifact: View {
        let title: String
        let subtitle: String
        let systemImage: String
        var tint: Color = .accentColor

        var body: some View {
            OnboardingGlassCard(
                cornerRadius: 28, fillOpacity: 0.12, strokeOpacity: 0.18, shadowOpacity: 0.18
            ) {
                HStack(alignment: .center, spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [tint.opacity(0.95), tint.opacity(0.35)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 72, height: 72)

                        Image(systemName: systemImage)
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(.white)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(title)
                            .font(.headline.weight(.semibold))

                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: - Components

    struct OnboardingBackButton: View {
        let action: () -> Void
        @State private var isHovering = false

        var body: some View {
            Button(action: action) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 48, height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.primary.opacity(isHovering ? 0.10 : 0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }
            .animation(.easeInOut(duration: 0.12), value: isHovering)
        }
    }

    struct OnboardingActionButton: View {
        let title: String
        var systemImage: String? = nil
        var isEnabled: Bool = true
        var background: Color = .accentColor
        var foreground: Color = .white
        var strokeColor: Color? = nil
        var minHeight: CGFloat = 50
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                HStack(spacing: 10) {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 18)
                    }

                    Text(title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))

                    Spacer(minLength: 0)
                }
                .foregroundStyle(foreground)
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
                .background(background)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(strokeColor ?? .clear, lineWidth: strokeColor == nil ? 0 : 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
            .opacity(isEnabled ? 1 : 0.55)
        }
    }

    struct OnboardingBrandActionButton: View {
        let title: String
        var background: Color
        var foreground: Color = .white
        var strokeColor: Color? = nil
        var minHeight: CGFloat = 52
        let action: () -> Void
        let leading: AnyView

        init<Leading: View>(
            title: String,
            background: Color,
            foreground: Color = .white,
            strokeColor: Color? = nil,
            minHeight: CGFloat = 52,
            @ViewBuilder _ leading: @escaping () -> Leading,
            action: @escaping () -> Void
        ) {
            self.title = title
            self.background = background
            self.foreground = foreground
            self.strokeColor = strokeColor
            self.minHeight = minHeight
            self.action = action
            self.leading = AnyView(leading())
        }

        var body: some View {
            Button(action: action) {
                HStack(spacing: 12) {
                    leading
                        .frame(width: 22, height: 22, alignment: .center)

                    Text(title)
                        .font(.system(size: 15, weight: .semibold))

                    Spacer(minLength: 0)
                }
                .foregroundStyle(foreground)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
                .background(background)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(strokeColor ?? .clear, lineWidth: strokeColor == nil ? 0 : 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    struct GoogleBrandMark: View {
        var body: some View {
            // Google "G" logo with proper brand colors
            Image(systemName: "g.circle.fill")
                .font(.system(size: 18))
                .symbolRenderingMode(.multicolor)
        }
    }

    /// Google Sign-In button following official branding guidelines
    /// Reference: https://developers.google.com/identity/branding-guidelines
    struct GoogleSignInButton: View {
        let action: () -> Void
        @Environment(\.colorScheme) private var colorScheme
        @State private var isHovering = false
        @State private var isPressed = false

        var body: some View {
            Button(action: action) {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)

                    // Google "G" logo
                    googleLogo

                    // Fixed spacing between logo and text
                    Spacer()
                        .frame(width: 10)

                    // Button text
                    Text("Sign in with Google")
                        .font(.custom("Roboto-Medium", size: 14))
                        .fallbackFont(.system(size: 14, weight: .medium))

                    Spacer(minLength: 0)
                }
                .frame(height: 48)
                .frame(maxWidth: .infinity)
                .background(backgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(borderColor, lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in isPressed = true }
                    .onEnded { _ in isPressed = false }
            )
        }

        private var googleLogo: some View {
            // Standard Google "G" logo
            // Using SF Symbol as placeholder - in production, use official Google logo SVG
            ZStack {
                Circle()
                    .fill(Color.white)
                    .frame(width: 18, height: 18)

                // Google "G" with brand colors
                Text("G")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(red: 0.26, green: 0.52, blue: 0.96),  // Google Blue
                                Color(red: 0.92, green: 0.25, blue: 0.21),  // Google Red
                                Color(red: 0.98, green: 0.74, blue: 0.02),  // Google Yellow
                                Color(red: 0.15, green: 0.68, blue: 0.38),  // Google Green
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        }

        private var backgroundColor: Color {
            switch colorScheme {
            case .light:
                // Light theme: #FFFFFF
                return isPressed ? Color(white: 0.95) : (isHovering ? Color(white: 0.98) : Color.white)
            case .dark:
                // Dark theme: #131314
                return isPressed
                    ? Color(red: 0.09, green: 0.09, blue: 0.10)
                    : (isHovering
                        ? Color(red: 0.10, green: 0.10, blue: 0.11) : Color(red: 0.075, green: 0.075, blue: 0.078))
            @unknown default:
                return Color.white
            }
        }

        private var borderColor: Color {
            switch colorScheme {
            case .light:
                // Light theme: #747775
                return Color(red: 0.455, green: 0.467, blue: 0.459)
            case .dark:
                // Dark theme: #8E918F
                return Color(red: 0.557, green: 0.569, blue: 0.561)
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
        @State private var isHovering = false
        @State private var isPressed = false

        var body: some View {
            Button(action: action) {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)

                    // Apple logo
                    appleLogo

                    // Fixed spacing between logo and text
                    Spacer()
                        .frame(width: 10)

                    // Button text
                    Text("Sign in with Apple")
                        .font(.system(size: 14, weight: .medium))

                    Spacer(minLength: 0)
                }
                .foregroundStyle(textColor)
                .frame(height: 48)
                .frame(maxWidth: .infinity)
                .background(backgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(borderColor, lineWidth: borderWidth)
                )
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in isPressed = true }
                    .onEnded { _ in isPressed = false }
            )
        }

        private var appleLogo: some View {
            Image(systemName: "apple.logo")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(logoColor)
        }

        private var backgroundColor: Color {
            switch colorScheme {
            case .light:
                // Light theme: white background
                return isPressed ? Color(white: 0.95) : (isHovering ? Color(white: 0.98) : Color.white)
            case .dark:
                // Dark theme: black background
                return isPressed ? Color(white: 0.05) : (isHovering ? Color(white: 0.03) : Color.black)
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
            return 1
        }
    }

    /// GitHub Sign-In button following GitHub branding guidelines
    /// Reference: https://github.com/logos
    struct GitHubSignInButton: View {
        let action: () -> Void
        @Environment(\.colorScheme) private var colorScheme
        @State private var isHovering = false
        @State private var isPressed = false

        var body: some View {
            Button(action: action) {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)

                    // GitHub logo
                    githubLogo

                    // Fixed spacing between logo and text
                    Spacer()
                        .frame(width: 10)

                    // Button text
                    Text("Continue with GitHub")
                        .font(.system(size: 14, weight: .medium))

                    Spacer(minLength: 0)
                }
                .foregroundStyle(textColor)
                .frame(height: 48)
                .frame(maxWidth: .infinity)
                .background(backgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(borderColor, lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in isPressed = true }
                    .onEnded { _ in isPressed = false }
            )
        }

        private var githubLogo: some View {
            // GitHub Invertocat logo
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(logoColor)
        }

        private var backgroundColor: Color {
            switch colorScheme {
            case .light:
                // Light theme: white background
                return isPressed ? Color(white: 0.95) : (isHovering ? Color(white: 0.98) : Color.white)
            case .dark:
                // Dark theme: dark background
                return isPressed
                    ? Color(red: 0.09, green: 0.09, blue: 0.10)
                    : (isHovering
                        ? Color(red: 0.10, green: 0.10, blue: 0.11) : Color(red: 0.075, green: 0.075, blue: 0.078))
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
                return Color(red: 0.455, green: 0.467, blue: 0.459)
            case .dark:
                return Color(red: 0.557, green: 0.569, blue: 0.561)
            @unknown default:
                return Color.gray
            }
        }
    }

    /// Microphone level meter for onboarding
    struct OnboardingMicrophoneLevelMeter: View {
        let level: Double

        private let barCount = 20
        private let spacing: CGFloat = 2

        var body: some View {
            GeometryReader { geometry in
                HStack(spacing: spacing) {
                    ForEach(0..<barCount, id: \.self) { index in
                        OnboardingLevelBar(
                            isActive: isBarActive(index: index),
                            height: barHeight(for: index, in: geometry.size.height)
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }

        private func isBarActive(index: Int) -> Bool {
            let threshold = Double(index) / Double(barCount)
            return level >= threshold
        }

        private func barHeight(for index: Int, in totalHeight: CGFloat) -> CGFloat {
            let centerIndex = barCount / 2
            let distanceFromCenter = abs(index - centerIndex)
            let maxHeight = totalHeight * 0.3
            let minHeight: CGFloat = 4

            let heightFactor = 1.0 - (Double(distanceFromCenter) / Double(centerIndex)) * 0.5
            return minHeight + (maxHeight - minHeight) * CGFloat(heightFactor)
        }
    }

    private struct OnboardingLevelBar: View {
        let isActive: Bool
        let height: CGFloat

        var body: some View {
            RoundedRectangle(cornerRadius: 2)
                .fill(isActive ? .green : Color.gray.opacity(0.3))
                .frame(height: height)
                .animation(.easeInOut(duration: 0.1), value: isActive)
        }
    }

    struct GitHubBrandMark: View {
        var body: some View {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 14, weight: .semibold))
        }
    }

    struct SummaryRow: View {
        let title: String
        let value: String

        var body: some View {
            HStack {
                Text(title)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(value)
                    .font(.system(.body, design: .rounded).weight(.medium))
            }
        }
    }

    struct StatusChecklistRow: View {
        let title: String
        let isComplete: Bool

        var body: some View {
            HStack(spacing: 10) {
                Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isComplete ? .green : .secondary)
                    .imageScale(.medium)

                Text(title)
                    .font(.subheadline)
            }
        }
    }

    struct PermissionGateRow<Actions: View>: View {
        let title: String
        let description: String
        let statusText: String
        let tint: Color
        @ViewBuilder let actions: () -> Actions

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.headline.weight(.semibold))

                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    MacSettingsStatusBadge(text: statusText, tint: tint)
                }

                actions()
            }
        }
    }

    // MARK: - Custom Input Controls

    /// Segmented-style picker rendered as pill buttons inside a glass track.
    struct OnboardingProviderPicker<Item>: View where Item: Hashable & Identifiable {
        let items: [Item]
        let displayName: (Item) -> String
        @Binding var selection: Item

        var body: some View {
            HStack(spacing: 4) {
                ForEach(items) { item in
                    let isSelected = selection == item
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) { selection = item }
                    } label: {
                        Text(displayName(item))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(isSelected ? .white : .secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(isSelected ? Color.accentColor : Color.clear)
                                    .shadow(
                                        color: isSelected ? Color.accentColor.opacity(0.28) : .clear,
                                        radius: 6, x: 0, y: 2
                                    )
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .animation(.easeInOut(duration: 0.18), value: isSelected)
                }
            }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.14))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
            )
        }
    }

    /// Glass-style labeled text or secure field matching the onboarding design system.
    struct OnboardingInputField: View {
        enum Mode { case text, secure }

        let label: String
        let placeholder: String
        @Binding var text: String
        var mode: Mode = .text
        var isMonospaced: Bool = false

        @FocusState private var isFocused: Bool

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text(label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            Color(nsColor: .controlBackgroundColor)
                                .opacity(isFocused ? 0.20 : 0.12))

                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            isFocused
                                ? Color.accentColor.opacity(0.45)
                                : Color.primary.opacity(0.12),
                            lineWidth: isFocused ? 1.5 : 1
                        )

                    Group {
                        if mode == .secure {
                            SecureField(placeholder, text: $text)
                        } else {
                            TextField(placeholder, text: $text)
                        }
                    }
                    .textFieldStyle(.plain)
                    .font(
                        isMonospaced
                            ? .system(.body, design: .monospaced)
                            : .body
                    )
                    .focused($isFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }
                .frame(minHeight: 36)
                .animation(.easeInOut(duration: 0.15), value: isFocused)
            }
        }
    }

    /// Glass-style social/OAuth sign-in button with a leading icon slot.
    struct OnboardingOAuthButton<Icon: View>: View {
        let title: String
        let action: () -> Void
        @ViewBuilder let icon: () -> Icon

        @State private var isHovering = false

        var body: some View {
            Button(action: action) {
                HStack(spacing: 12) {
                    icon()
                        .frame(width: 20, height: 20)

                    Text(title)
                        .font(.system(size: 14, weight: .semibold))

                    Spacer(minLength: 0)
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            Color(nsColor: .controlBackgroundColor)
                                .opacity(isHovering ? 0.22 : 0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }
            .animation(.easeInOut(duration: 0.12), value: isHovering)
        }
    }

    // MARK: - Visual Panel

    private final class OnboardingKeyboardMonitor: ObservableObject {
        @Published var pressedKeys: Set<UInt16> = []
        @Published var modifierFlags: CGEventFlags = []

        private enum Backend {
            case eventTap(CFMachPort, CFRunLoopSource)
            case localMonitor(Any)
        }

        private var backend: Backend?

        func start() {
            guard backend == nil else { return }

            if installEventTap() {
                return
            }

            installLocalMonitor()
        }

        func stop() {
            switch backend {
            case .eventTap(let tap, let source):
                CGEvent.tapEnable(tap: tap, enable: false)
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            case .localMonitor(let localMonitor):
                NSEvent.removeMonitor(localMonitor)
            case .none:
                break
            }

            backend = nil
            pressedKeys.removeAll()
            modifierFlags = []
        }

        deinit {
            stop()
        }

        private func installEventTap() -> Bool {
            if #available(macOS 10.15, *) {
                guard CGPreflightListenEventAccess() else {
                    return false
                }
            }

            let eventMask: CGEventMask =
                (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
                | (1 << CGEventType.flagsChanged.rawValue)

            guard
                let tap = CGEvent.tapCreate(
                    tap: .cgSessionEventTap,
                    place: .headInsertEventTap,
                    options: .listenOnly,
                    eventsOfInterest: eventMask,
                    callback: { _, type, event, refcon in
                        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                            return Unmanaged.passUnretained(event)
                        }

                        guard let refcon else {
                            return Unmanaged.passUnretained(event)
                        }

                        let monitor = Unmanaged<OnboardingKeyboardMonitor>
                            .fromOpaque(refcon)
                            .takeUnretainedValue()
                        monitor.handle(type: type, event: event)
                        return Unmanaged.passUnretained(event)
                    },
                    userInfo: Unmanaged.passUnretained(self).toOpaque()
                )
            else {
                return false
            }

            guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
                CGEvent.tapEnable(tap: tap, enable: false)
                return false
            }

            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            backend = .eventTap(tap, source)
            return true
        }

        private func installLocalMonitor() {
            if let monitor =
                (NSEvent.addLocalMonitorForEvents(
                    matching: [.keyDown, .keyUp, .flagsChanged]
                ) { [weak self] event in
                    self?.handle(event)
                    return event
                })
            {
                backend = .localMonitor(monitor)
            }
        }

        private func handle(_ event: NSEvent) {
            switch event.type {
            case .keyDown:
                if !event.isARepeat {
                    pressedKeys.insert(event.keyCode)
                }
            case .keyUp:
                pressedKeys.remove(event.keyCode)
            case .flagsChanged:
                modifierFlags = CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue))
            default:
                break
            }
        }

        private func handle(type: CGEventType, event: CGEvent) {
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

            switch type {
            case .keyDown:
                if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                    pressedKeys.insert(keyCode)
                }
            case .keyUp:
                pressedKeys.remove(keyCode)
            case .flagsChanged:
                modifierFlags = event.flags
            default:
                break
            }
        }
    }

    struct OnboardingKeyboardView: View {
        @StateObject private var keyboardMonitor = OnboardingKeyboardMonitor()

        // Key codes: Z=6, X=7, C=8, V=9, space=49, period=47

        var body: some View {
            VStack(spacing: 30) {
                VStack(alignment: .trailing, spacing: 12) {
                    // Row 1: N, M, ,, ., /, Shift
                    HStack(spacing: 10) {
                        KeyCap(
                            text: "N", subtext: nil, icon: nil, width: 50,
                            isPressed: keyboardMonitor.pressedKeys.contains(45))
                        KeyCap(
                            text: "M", subtext: nil, icon: nil, width: 50,
                            isPressed: keyboardMonitor.pressedKeys.contains(46))
                        KeyCap(
                            text: ",", subtext: nil, icon: nil, width: 50,
                            isPressed: keyboardMonitor.pressedKeys.contains(43))
                        KeyCap(
                            text: ".", subtext: nil, icon: nil, width: 50,
                            isPressed: keyboardMonitor.pressedKeys.contains(47))
                        KeyCap(
                            text: "/", subtext: "?", icon: nil, width: 50,
                            isPressed: keyboardMonitor.pressedKeys.contains(44))
                        KeyCap(
                            text: "⇧", subtext: nil, icon: nil, width: 90,
                            isPressed: keyboardMonitor.modifierFlags.contains(.maskShift))
                    }

                    // Row 2: Space, Command (R), Option (R), Arrows
                    HStack(alignment: .bottom, spacing: 10) {
                        KeyCap(
                            text: "space", subtext: nil, icon: nil, width: 130,
                            isPressed: keyboardMonitor.pressedKeys.contains(49))
                        KeyCap(
                            text: "command", subtext: "⌘", icon: nil, width: 70,
                            isPressed: keyboardMonitor.modifierFlags.contains(.maskCommand))
                        KeyCap(
                            text: "option", subtext: "⌥", icon: nil, width: 60,
                            isPressed: keyboardMonitor.modifierFlags.contains(.maskAlternate))

                        HStack(alignment: .bottom, spacing: 4) {
                            KeyCap(
                                text: "", subtext: nil, icon: "chevron.left", width: 44, height: 23,
                                isPressed: keyboardMonitor.pressedKeys.contains(123))

                            VStack(spacing: 4) {
                                KeyCap(
                                    text: "", subtext: nil, icon: "chevron.up", width: 44,
                                    height: 23, isPressed: keyboardMonitor.pressedKeys.contains(126)
                                )
                                KeyCap(
                                    text: "", subtext: nil, icon: "chevron.down", width: 44,
                                    height: 23, isPressed: keyboardMonitor.pressedKeys.contains(125)
                                )
                            }

                            KeyCap(
                                text: "", subtext: nil, icon: "chevron.right", width: 44,
                                height: 23, isPressed: keyboardMonitor.pressedKeys.contains(124))
                        }
                    }
                }

                Text("When pressed, do you see the button turn black?")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.8))
            }
            .onAppear {
                keyboardMonitor.start()
            }
            .onDisappear {
                keyboardMonitor.stop()
            }
        }
    }

    private struct KeyCap: View {
        let text: String
        let subtext: String?
        let icon: String?
        let width: CGFloat
        var height: CGFloat = 50
        let isPressed: Bool

        var body: some View {
            VStack(spacing: 2) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 10))
                        .frame(maxWidth: .infinity, alignment: text.isEmpty ? .center : .leading)
                        .padding(.leading, text.isEmpty ? 0 : 6)
                        .padding(.top, 4)
                }

                if let subtext {
                    Text(subtext)
                        .font(.system(size: 10))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 4)
                }

                Spacer(minLength: 0)

                if !text.isEmpty {
                    Text(text)
                        .font(.system(size: 13, weight: .regular))
                        .frame(
                            maxWidth: .infinity,
                            alignment: icon != nil && !text.isEmpty ? .leading : .center
                        )
                        .padding(.leading, icon != nil && !text.isEmpty ? 6 : 0)
                        .padding(.bottom, 6)
                }
            }
            .frame(width: width, height: height)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isPressed ? Color.black : Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isPressed ? Color.clear : Color.black.opacity(0.1), lineWidth: 1)
            )
            .foregroundStyle(isPressed ? Color.white : Color.black.opacity(0.6))
            .shadow(color: Color.black.opacity(isPressed ? 0 : 0.05), radius: 2, x: 0, y: 1)
            .animation(.easeInOut(duration: 0.1), value: isPressed)
        }
    }

    struct OnboardingVisualPanel: View {
        let step: MacOnboardingStep
        let viewModel: OnboardingViewModel
        let onAppearanceThemeChange: ((MacDictationVisualTheme) -> Void)?
        @State private var firstSuccessDraftText = ""
        @FocusState private var isFirstSuccessDraftFocused: Bool

        init(
            step: MacOnboardingStep,
            viewModel: OnboardingViewModel,
            onAppearanceThemeChange: ((MacDictationVisualTheme) -> Void)? = nil
        ) {
            self.step = step
            self.viewModel = viewModel
            self.onAppearanceThemeChange = onAppearanceThemeChange
        }

        var body: some View {
            ZStack {
                if step == .appearance {
                    backgroundGradient
                }

                if step == .shortcut {
                    OnboardingKeyboardView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(32)
                } else if step == .permissions {
                    // Microphone test panel
                    VStack(spacing: 24) {
                        Spacer()

                        // Microphone level meter
                        OnboardingMicrophoneLevelMeter(level: 0.0)
                            .frame(height: 40)
                            .padding(.horizontal, 0)

                        // Start recording button
                        OnboardingActionButton(
                            title: "Start Recording",
                            systemImage: "record.circle",
                            background: Color.white.opacity(0.08),
                            foreground: .primary,
                            strokeColor: Color.white.opacity(0.10),
                            minHeight: 48
                        ) {
                            // TODO: Implement recording
                        }
                        .frame(width: 316)

                        Spacer()
                    }
                    .padding(32)
                } else if step == .firstSuccess {
                    // Voice input test panel
                    VStack(spacing: 24) {
                        Spacer()

                        // Prompt text
                        VStack(spacing: 8) {
                            Text("Try saying:")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text("Hello, this is a test")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(.primary)
                        }

                        // Input box
                        ZStack(alignment: .topLeading) {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color(nsColor: .textBackgroundColor).opacity(0.72))

                            TextField(
                                "",
                                text: $firstSuccessDraftText,
                                axis: .vertical
                            )
                            .textFieldStyle(.plain)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .focused($isFirstSuccessDraftFocused)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 16)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        }
                        .frame(height: 120)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                        )

                        // Interactive hotkey display
                        OnboardingHotkeyDisplay()

                        Spacer()
                    }
                    .padding(32)
                    .onAppear {
                        if firstSuccessDraftText.isEmpty {
                            firstSuccessDraftText = viewModel.firstSuccessPreviewText ?? ""
                        }
                        isFirstSuccessDraftFocused = true
                    }
                } else if step == .appearance {
                    OnboardingAppearanceCoverFlowPanel(
                        onFocusedThemeChange: { theme in
                            onAppearanceThemeChange?(theme)
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(18)
                } else if step == .done {
                    // Empty panel for appearance/theme selection
                    VStack {
                        Spacer()
                        // TODO: Add theme selection UI here
                        Spacer()
                    }
                    .padding(32)
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .center, spacing: 12) {
                            OnboardingPill(
                                text: "Live preview", systemImage: "sparkles", tint: accentColor)

                            Spacer(minLength: 0)

                            Image(systemName: stepSystemImage)
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(accentColor)
                                .padding(10)
                                .background(
                                    Circle()
                                        .fill(accentColor.opacity(0.12))
                                )
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text(panelTitle)
                                .font(.system(size: 24, weight: .semibold, design: .rounded))

                            Text(panelSubtitle)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        OnboardingStageArtifact(
                            title: heroTitle,
                            subtitle: heroSubtitle,
                            systemImage: stepSystemImage,
                            tint: accentColor
                        )

                        VStack(spacing: 10) {
                            ForEach(metrics) { metric in
                                OnboardingGlassCard(
                                    cornerRadius: 18, fillOpacity: 0.08, strokeOpacity: 0.14,
                                    shadowOpacity: 0.08
                                ) {
                                    OnboardingMetricCard(
                                        title: metric.title,
                                        value: metric.value,
                                        systemImage: metric.systemImage,
                                        tint: metric.tint
                                    )
                                }
                            }
                        }

                        OnboardingGlassCard(
                            cornerRadius: 18, fillOpacity: 0.06, strokeOpacity: 0.10,
                            shadowOpacity: 0.06
                        ) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(footerTitle)
                                    .font(.subheadline.weight(.semibold))

                                Text(footerSubtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(22)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.16), radius: 24, x: 0, y: 12)
            .accessibilityHidden(true)
        }

        private var backgroundGradient: some View {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(nsColor: .controlBackgroundColor).opacity(0.96),
                        accentColor.opacity(0.10),
                        Color(nsColor: .controlBackgroundColor).opacity(0.88),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                RadialGradient(
                    colors: [accentColor.opacity(0.28), .clear],
                    center: .topLeading,
                    startRadius: 20,
                    endRadius: 280
                )
                .blur(radius: 2)

                RadialGradient(
                    colors: [accentColor.opacity(0.18), .clear],
                    center: .bottomTrailing,
                    startRadius: 20,
                    endRadius: 220
                )
                .blur(radius: 2)
            }
        }

        private var panelTitle: String {
            switch step {
            case .apiKey:
                return "Verify access"
            case .permissions:
                return "Grant the basics"
            case .shortcut:
                return "Set your shortcut"
            case .firstSuccess:
                return "Say something in the box"
            case .done:
                return "Ready to go"
            default:
                return ""
            }
        }

        private var panelSubtitle: String {
            switch step {
            case .apiKey:
                return "Choose a provider, enter a key, and continue once it validates."
            case .permissions:
                return "Mic and input control remain the only permissions Stet needs."
            case .shortcut:
                return "Choose the shortcut you want to use."
            case .firstSuccess:
                return "Click the text box, then use your hotkey to speak a sentence."
            case .done:
                return "Everything needed for the onboarding path is now in place."
            default:
                return ""
            }
        }

        private var heroTitle: String {
            switch step {
            case .apiKey:
                return "\(viewModel.apiKeyProvider.displayName) key"
            case .permissions:
                return "Permission ready state"
            case .shortcut:
                return viewModel.shortcutSummaryText
            case .firstSuccess:
                return viewModel.firstSuccessPreviewText ?? "Awaiting first capture"
            case .done:
                return "You're all set."
            default:
                return ""
            }
        }

        private var heroSubtitle: String {
            switch step {
            case .apiKey:
                return isAPIKeyValidated
                    ? "The current key is verified and ready for use."
                    : "Enter a key from your provider and verify it before proceeding."
            case .permissions:
                return viewModel.hasRequiredPermissions
                    ? "Everything required has been detected."
                    : "The onboarding flow still needs microphone and input control permissions."
            case .shortcut:
                return "The shortcut is ready to use."
            case .firstSuccess:
                return viewModel.canContinueFirstSuccessOnboarding
                    ? "A successful result is visible in the box."
                    : "Speak naturally and let the first pass finish."
            case .done:
                return "The onboarding path is complete and the app is ready to use."
            default:
                return ""
            }
        }

        private var footerTitle: String {
            switch step {
            case .apiKey:
                return "Provider-aware"
            case .permissions:
                return "Use only what is needed"
            case .shortcut:
                return "Shortcut setup"
            case .firstSuccess:
                return "Live input check"
            case .done:
                return "Start dictating anywhere"
            default:
                return ""
            }
        }

        private var footerSubtitle: String {
            switch step {
            case .apiKey:
                return "This path still saves and validates the provider key before advancing."
            case .permissions:
                return "Permission checks remain exactly where the app expects them."
            case .shortcut:
                return "The recorder is all you need here."
            case .firstSuccess:
                return "This step now exercises a real text target."
            case .done:
                return "Finish the flow and begin using the app immediately."
            default:
                return ""
            }
        }

        private var accentColor: Color {
            switch step {
            case .apiKey:
                return .orange
            case .permissions:
                return .green
            case .shortcut:
                return .pink
            case .firstSuccess:
                return .mint
            case .done:
                return .purple
            default:
                return .accentColor
            }
        }

        private var stepSystemImage: String {
            switch step {
            case .apiKey:
                return "key.fill"
            case .permissions:
                return "shield.checkerboard"
            case .shortcut:
                return "keyboard"
            case .firstSuccess:
                return "waveform"
            case .done:
                return "checkmark.seal.fill"
            default:
                return "sparkles"
            }
        }

        private var isAPIKeyValidated: Bool {
            viewModel.isAPIKeyValidated
        }

        private var metrics: [OnboardingVisualMetric] {
            switch step {
            case .apiKey:
                return [
                    .init(
                        title: "Provider", value: viewModel.apiKeyProvider.displayName,
                        systemImage: "server.rack", tint: .orange),
                    .init(
                        title: "Status", value: isAPIKeyValidated ? "Verified" : "Awaiting key",
                        systemImage: "checkmark.shield", tint: .green),
                    .init(
                        title: "Storage", value: "Saved in Keychain", systemImage: "lock.shield",
                        tint: .blue),
                ]
            case .permissions:
                return [
                    .init(
                        title: "Microphone", value: viewModel.microphoneAccessStatusText,
                        systemImage: "mic.fill",
                        tint: viewModel.microphoneAccessNeedsAttention ? .orange : .green),
                    .init(
                        title: "Input control", value: viewModel.autoPasteStatusText,
                        systemImage: "keyboard",
                        tint: viewModel.autoPasteAccessNeedsAttention ? .orange : .green),
                    .init(
                        title: "Ready",
                        value: viewModel.hasRequiredPermissions ? "Yes" : "Needs attention",
                        systemImage: "checkmark.circle.fill",
                        tint: viewModel.hasRequiredPermissions ? .green : .orange),
                ]
            case .shortcut:
                return [
                    .init(
                        title: "Shortcut", value: viewModel.shortcutSummaryText,
                        systemImage: "keyboard", tint: .pink),
                    .init(
                        title: "Next", value: "Continue to first run",
                        systemImage: "arrow.right.circle.fill", tint: .blue),
                    .init(
                        title: "Later", value: "Adjust in Settings", systemImage: "gearshape",
                        tint: .green),
                ]
            case .firstSuccess:
                return [
                    .init(
                        title: "Result",
                        value: viewModel.firstSuccessPreviewText ?? "No preview yet",
                        systemImage: "text.quote", tint: .mint),
                    .init(
                        title: "Gate",
                        value: viewModel.canContinueFirstSuccessOnboarding ? "Open" : "Waiting",
                        systemImage: "checkmark.circle", tint: .green),
                    .init(
                        title: "Fallback",
                        value: viewModel.canSkipFirstSuccessOnboarding
                            ? "Skip allowed" : "Required", systemImage: "arrow.right.circle",
                        tint: .orange),
                ]
            case .done:
                return [
                    .init(
                        title: "Shortcut", value: viewModel.shortcutSummaryText,
                        systemImage: "keyboard", tint: .purple),
                    .init(
                        title: "Mode",
                        value: viewModel.onboardingMode == .apiKey ? "API Key" : "Logged In",
                        systemImage: "arrow.triangle.branch", tint: .blue),
                    .init(
                        title: "Permissions",
                        value: viewModel.hasRequiredPermissions ? "Enabled" : "Check required",
                        systemImage: "shield.checkerboard", tint: .green),
                ]
            default:
                return []
            }
        }

        private struct OnboardingVisualMetric: Identifiable {
            let id = UUID()
            let title: String
            let value: String
            let systemImage: String
            let tint: Color
        }
    }

    private struct OnboardingAppearanceCoverFlowPanel: View {
        private struct CardSpec: Identifiable {
            let id = UUID()
            let theme: MacDictationVisualTheme
            let badge: String
            let color: Color
            let imageName: String?
            let swatches: [Color]?
        }

        private struct LayoutSpec {
            let size: CGSize
            let xOffset: CGFloat
            let yOffset: CGFloat
            let yRotation: Double
            let scale: CGFloat
            let opacity: Double
            let zIndex: Double
            let isInteractive: Bool
        }

        private struct SwatchSpec {
            let color: Color
        }

        @State private var focusedIndex = 0
        private let onFocusedThemeChange: (MacDictationVisualTheme) -> Void

        init(onFocusedThemeChange: @escaping (MacDictationVisualTheme) -> Void = { _ in }) {
            self.onFocusedThemeChange = onFocusedThemeChange
        }

        private let cards: [CardSpec] = [
            .init(
                theme: .blossom,
                badge: "01",
                color: Color(red: 0.95, green: 0.78, blue: 0.84),
                imageName: "flower",
                swatches: [
                    Color(hex: "#87b3e2"),
                    Color(hex: "#b7cb5c"),
                    Color(hex: "#e78e92"),
                ]
            ),
            .init(
                theme: .egg,
                badge: "02",
                color: Color(red: 0.20, green: 0.64, blue: 0.45),
                imageName: "onboardingEgg",
                swatches: [
                    Color(hex: "#5e8da7"),
                    Color(hex: "#dc9803"),
                    Color(hex: "#cacabf"),
                ]
            ),
            .init(
                theme: .harbor,
                badge: "03",
                color: Color(red: 0.93, green: 0.50, blue: 0.24),
                imageName: "onboardingArch",
                swatches: [
                    Color(hex: "#014c69"),
                    Color(hex: "#3a2520"),
                    Color(hex: "#b05e5b"),
                ]
            ),
            .init(
                theme: .cat,
                badge: "04",
                color: Color(red: 0.70, green: 0.38, blue: 0.90),
                imageName: "onboardingFloat",
                swatches: [
                    Color(hex: "#a22e2e"),
                    Color(hex: "#191718"),
                    Color(hex: "#eeeced"),
                ]
            ),
            .init(
                theme: .beacon,
                badge: "05",
                color: Color(red: 0.95, green: 0.73, blue: 0.20),
                imageName: "onboardingPanel5",
                swatches: [
                    Color(hex: "#053447"),
                    Color(hex: "#0451ad"),
                    Color(hex: "#efa50f"),
                ]
            ),
            .init(
                theme: .autumn,
                badge: "06",
                color: Color(red: 0.29, green: 0.78, blue: 0.76),
                imageName: "autumn",
                swatches: [
                    Color(hex: "#fdc24e"),
                    Color(hex: "#fe4c45"),
                    Color(hex: "#187789"),
                ]
            ),
        ]

        var body: some View {
            VStack(spacing: 16) {
                Spacer(minLength: 0)

                HStack(spacing: 12) {
                    ForEach(swatchSpecs(for: focusedIndex).indices, id: \.self) { index in
                        let swatch = swatchSpecs(for: focusedIndex)[index]

                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(swatch.color)
                            .frame(width: 46, height: 46)
                            .shadow(color: Color.black.opacity(0.22), radius: 10, x: 0, y: 6)
                    }
                }
                .animation(.spring(response: 0.45, dampingFraction: 0.82), value: focusedIndex)

                ZStack {
                    ForEach(cards.indices, id: \.self) { index in
                        let card = cards[index]
                        let relativeOffset = relativeOffset(for: index)
                        let layout = layout(for: relativeOffset)

                        OnboardingCoverFlowCard(
                            badge: card.badge,
                            color: card.color,
                            imageName: card.imageName
                        )
                        .frame(width: layout.size.width, height: layout.size.height)
                        .scaleEffect(layout.scale)
                        .rotation3DEffect(
                            .degrees(layout.yRotation),
                            axis: (x: 0, y: 1, z: 0),
                            perspective: 0.78
                        )
                        .offset(x: layout.xOffset, y: layout.yOffset)
                        .opacity(layout.opacity)
                        .zIndex(layout.zIndex)
                        .allowsHitTesting(layout.isInteractive)
                        .onTapGesture {
                            guard relativeOffset == -1 || relativeOffset == 1 else { return }
                            rotateFocus(by: relativeOffset)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .animation(.spring(response: 0.45, dampingFraction: 0.82), value: focusedIndex)

                Spacer(minLength: 0)
            }
            .padding(.vertical, 8)
            .onAppear {
                onFocusedThemeChange(currentFocusedTheme)
            }
        }

        private func swatchSpecs(for focusedIndex: Int) -> [SwatchSpec] {
            let card = cards[normalizedIndex(focusedIndex)]
            if let swatches = card.swatches, swatches.count == 3 {
                return swatches.map { SwatchSpec(color: $0) }
            }

            return [
                SwatchSpec(color: card.color.opacity(0.96)),
                SwatchSpec(color: card.color.opacity(0.72)),
                SwatchSpec(color: card.color.opacity(0.54)),
            ]
        }

        private func relativeOffset(for index: Int) -> Int {
            guard !cards.isEmpty else { return 0 }

            let count = cards.count
            var offset = index - focusedIndex
            if offset > count / 2 {
                offset -= count
            }
            if offset < -(count / 2) {
                offset += count
            }
            return offset
        }

        private func layout(for offset: Int) -> LayoutSpec {
            switch offset {
            case 0:
                return LayoutSpec(
                    size: CGSize(width: 210, height: 294),
                    xOffset: 0,
                    yOffset: 0,
                    yRotation: 0,
                    scale: 1.0,
                    opacity: 1.0,
                    zIndex: 3,
                    isInteractive: false
                )
            case -1:
                return LayoutSpec(
                    size: CGSize(width: 150, height: 224),
                    xOffset: -148,
                    yOffset: 18,
                    yRotation: 28,
                    scale: 0.92,
                    opacity: 1.0,
                    zIndex: 2,
                    isInteractive: true
                )
            case 1:
                return LayoutSpec(
                    size: CGSize(width: 150, height: 224),
                    xOffset: 148,
                    yOffset: 18,
                    yRotation: -28,
                    scale: 0.92,
                    opacity: 1.0,
                    zIndex: 1,
                    isInteractive: true
                )
            default:
                let hiddenIsLeft = offset < 0
                return LayoutSpec(
                    size: CGSize(width: 150, height: 224),
                    xOffset: hiddenIsLeft ? -280 : 280,
                    yOffset: 28,
                    yRotation: hiddenIsLeft ? 34 : -34,
                    scale: 0.8,
                    opacity: 0.0,
                    zIndex: 0,
                    isInteractive: false
                )
            }
        }

        private func rotateFocus(by delta: Int) {
            guard delta != 0 else { return }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                focusedIndex = normalizedIndex(focusedIndex + delta)
            }
            onFocusedThemeChange(currentFocusedTheme)
        }

        private func normalizedIndex(_ index: Int) -> Int {
            guard !cards.isEmpty else { return 0 }
            let modulo = index % cards.count
            return modulo >= 0 ? modulo : modulo + cards.count
        }

        private var currentFocusedTheme: MacDictationVisualTheme {
            cards[normalizedIndex(focusedIndex)].theme
        }
    }

    private struct OnboardingCoverFlowCard: View {
        let badge: String
        let color: Color
        let imageName: String?

        var body: some View {
            ZStack(alignment: .topTrailing) {
                if let imageName {
                    Image(imageName)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                } else {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(color)
                }

                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(imageName == nil ? 0.12 : 0.18),
                                Color.white.opacity(imageName == nil ? 0.04 : 0.08),
                                .clear,
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                if imageName != nil {
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.02),
                            Color.black.opacity(0.12),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }

                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: Color.black.opacity(0.30), radius: 18, x: 0, y: 12)
        }
    }

    /// Interactive hotkey display that shows pressed keys
    struct OnboardingHotkeyDisplay: View {
        @StateObject private var keyboardMonitor = OnboardingKeyboardMonitor()

        var body: some View {
            VStack(spacing: 12) {
                Text("Press your hotkey")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    // Command key
                    KeyCap(
                        text: "command", subtext: "⌘", icon: nil, width: 80,
                        isPressed: keyboardMonitor.modifierFlags.contains(.maskCommand))

                    Text("+")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.secondary)

                    // Period key (default)
                    KeyCap(
                        text: ".", subtext: nil, icon: nil, width: 50,
                        isPressed: keyboardMonitor.pressedKeys.contains(47))
                }
            }
            .onAppear {
                keyboardMonitor.start()
            }
            .onDisappear {
                keyboardMonitor.stop()
            }
        }
    }

#endif
