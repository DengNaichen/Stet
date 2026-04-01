#if os(macOS)
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
                .frame(height: 48)
                .animation(.easeInOut(duration: 0.15), value: isFocused)
            }
        }
    }

#endif
