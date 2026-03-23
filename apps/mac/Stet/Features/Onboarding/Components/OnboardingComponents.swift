#if os(macOS)
import Foundation
import SwiftUI

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
        OnboardingGlassCard(cornerRadius: 28, fillOpacity: 0.12, strokeOpacity: 0.18, shadowOpacity: 0.18) {
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

struct OnboardingChoiceCard: View {
    let title: String
    let details: [String]
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        OnboardingGlassCard(cornerRadius: 22, fillOpacity: 0.12, strokeOpacity: 0.18) {
            VStack(alignment: .leading, spacing: 14) {
                Text(title)
                    .font(.headline.weight(.semibold))

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(details, id: \.self) { detail in
                        BulletRow(text: detail)
                    }
                }

                Spacer(minLength: 0)

                OnboardingActionButton(
                    title: buttonTitle,
                    background: Color.accentColor,
                    foreground: .white,
                    minHeight: 48,
                    action: action
                )
            }
            .frame(maxWidth: .infinity, minHeight: 172, alignment: .topLeading)
        }
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
        ZStack {
            Circle()
                .fill(Color.white)
                .frame(width: 18, height: 18)

            Text("G")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .red, .yellow, .green],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
    }
}

struct GitHubBrandMark: View {
    var body: some View {
        Image(systemName: "chevron.left.forwardslash.chevron.right")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
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

// MARK: - Visual Panel

struct CleanGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let label = configuration.label as? Text {
                label
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
            }

            configuration.content
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.78))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 5)
    }
}

struct OnboardingVisualPanel: View {
    let step: MacOnboardingStep
    let viewModel: OnboardingViewModel

    var body: some View {
        ZStack {
            backgroundGradient

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 12) {
                    OnboardingPill(text: "Live preview", systemImage: "sparkles", tint: accentColor)

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
                        OnboardingGlassCard(cornerRadius: 18, fillOpacity: 0.08, strokeOpacity: 0.14, shadowOpacity: 0.08) {
                            OnboardingMetricCard(
                                title: metric.title,
                                value: metric.value,
                                systemImage: metric.systemImage,
                                tint: metric.tint
                            )
                        }
                    }
                }

                OnboardingGlassCard(cornerRadius: 18, fillOpacity: 0.06, strokeOpacity: 0.10, shadowOpacity: 0.06) {
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
                    Color(nsColor: .controlBackgroundColor).opacity(0.88)
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
        case .welcome:
            return "A cleaner start"
        case .mode:
            return "Pick your path"
        case .apiKey:
            return "Verify access"
        case .login:
            return "Sign in and sync"
        case .permissions:
            return "Grant the basics"
        case .shortcut:
            return "Set your shortcut"
        case .firstSuccess:
            return "Try a real sentence"
        case .done:
            return "Ready to go"
        }
    }

    private var panelSubtitle: String {
        switch step {
        case .welcome:
            return "The same onboarding flow, presented with a cleaner visual hierarchy."
        case .mode:
            return "Managed login and BYOK still lead to the same next steps."
        case .apiKey:
            return "Choose a provider, enter a key, and continue once it validates."
        case .login:
            return "Use Google, GitHub, or email to finish the managed path."
        case .permissions:
            return "Mic and input control remain the only permissions Stet needs."
        case .shortcut:
            return "Record the shortcut once, then test it before continuing."
        case .firstSuccess:
            return "Your first pass proves the flow works end to end."
        case .done:
            return "Everything needed for the onboarding path is now in place."
        }
    }

    private var heroTitle: String {
        switch step {
        case .welcome:
            return "Fast setup. Fewer distractions."
        case .mode:
            return "Two options, one flow."
        case .apiKey:
            return "\(viewModel.apiKeyProvider.displayName) key"
        case .login:
            return viewModel.relaySessionEmail ?? "Managed account"
        case .permissions:
            return "Permission ready state"
        case .shortcut:
            return viewModel.shortcutSummaryText
        case .firstSuccess:
            return viewModel.firstSuccessPreviewText ?? "Awaiting first capture"
        case .done:
            return "You're all set."
        }
    }

    private var heroSubtitle: String {
        switch step {
        case .welcome:
            return "Native Mac UI, clear progression, and no extra setup noise."
        case .mode:
            return "Choose API key or login, then continue with the same onboarding sequence."
        case .apiKey:
            return isAPIKeyValidated
                ? "The current key is verified and ready for use."
                : "Enter a key from your provider and verify it before proceeding."
        case .login:
            return viewModel.isRelaySessionActive
                ? "Signed in and ready to continue."
                : "Use a supported provider or email to complete the managed path."
        case .permissions:
            return viewModel.hasRequiredPermissions
                ? "Everything required has been detected."
                : "The onboarding flow still needs microphone and input control permissions."
        case .shortcut:
            return viewModel.canContinueShortcutOnboarding
                ? "The shortcut test has completed."
                : "Press and hold the configured shortcut to validate the capture loop."
        case .firstSuccess:
            return viewModel.canContinueFirstSuccessOnboarding
                ? "A successful result is available."
                : "Speak naturally and let the first pass finish."
        case .done:
            return "The onboarding path is complete and the app is ready to use."
        }
    }

    private var footerTitle: String {
        switch step {
        case .welcome:
            return "Built for the same workflow"
        case .mode:
            return "No branching complexity"
        case .apiKey:
            return "Provider-aware"
        case .login:
            return "Managed services enabled"
        case .permissions:
            return "Use only what is needed"
        case .shortcut:
            return "A fast test loop"
        case .firstSuccess:
            return "Proof of life"
        case .done:
            return "Start dictating anywhere"
        }
    }

    private var footerSubtitle: String {
        switch step {
        case .welcome:
            return "The shell changes, but the step order and actions stay the same."
        case .mode:
            return "Your choice only determines which existing step comes next."
        case .apiKey:
            return "This path still saves and validates the provider key before advancing."
        case .login:
            return "A successful sign-in still leads straight through the existing flow."
        case .permissions:
            return "Permission checks remain exactly where the app expects them."
        case .shortcut:
            return "The recorder, test press, and completion logic are untouched."
        case .firstSuccess:
            return "The preview result is still the same success gate used today."
        case .done:
            return "Finish the flow and begin using the app immediately."
        }
    }

    private var accentColor: Color {
        switch step {
        case .welcome:
            return .blue
        case .mode:
            return .teal
        case .apiKey:
            return .orange
        case .login:
            return .indigo
        case .permissions:
            return .green
        case .shortcut:
            return .pink
        case .firstSuccess:
            return .mint
        case .done:
            return .purple
        }
    }

    private var stepSystemImage: String {
        switch step {
        case .welcome:
            return "sparkles"
        case .mode:
            return "arrow.triangle.branch"
        case .apiKey:
            return "key.fill"
        case .login:
            return "person.crop.circle.badge.checkmark"
        case .permissions:
            return "shield.checkerboard"
        case .shortcut:
            return "keyboard"
        case .firstSuccess:
            return "waveform"
        case .done:
            return "checkmark.seal.fill"
        }
    }

    private var isAPIKeyValidated: Bool {
        viewModel.isAPIKeyValidated
    }

    private var metrics: [OnboardingVisualMetric] {
        switch step {
        case .welcome:
            return [
                .init(title: "Mode", value: "API Key or login", systemImage: "arrow.triangle.branch", tint: .blue),
                .init(title: "Style", value: "Native Mac", systemImage: "macwindow", tint: .teal),
                .init(title: "Focus", value: "Fewer interruptions", systemImage: "sparkles", tint: .purple),
            ]
        case .mode:
            return [
                .init(title: "BYOK", value: "Your provider", systemImage: "key.fill", tint: .orange),
                .init(title: "Managed", value: "Login flow", systemImage: "person.crop.circle.badge.checkmark", tint: .indigo),
                .init(title: "Next", value: "Permissions", systemImage: "arrow.right.circle.fill", tint: .green),
            ]
        case .apiKey:
            return [
                .init(title: "Provider", value: viewModel.apiKeyProvider.displayName, systemImage: "server.rack", tint: .orange),
                .init(title: "Status", value: isAPIKeyValidated ? "Verified" : "Awaiting key", systemImage: "checkmark.shield", tint: .green),
                .init(title: "Storage", value: "Saved in Keychain", systemImage: "lock.shield", tint: .blue),
            ]
        case .login:
            return [
                .init(title: "Session", value: viewModel.relaySessionEmail ?? "Not signed in", systemImage: "person.text.rectangle", tint: .indigo),
                .init(title: "Providers", value: "Google, GitHub, Email", systemImage: "person.2.fill", tint: .blue),
                .init(title: "Continue", value: "Managed flow", systemImage: "arrow.right.circle.fill", tint: .green),
            ]
        case .permissions:
            return [
                .init(title: "Microphone", value: viewModel.microphoneAccessStatusText, systemImage: "mic.fill", tint: viewModel.microphoneAccessNeedsAttention ? .orange : .green),
                .init(title: "Input control", value: viewModel.autoPasteStatusText, systemImage: "keyboard", tint: viewModel.autoPasteAccessNeedsAttention ? .orange : .green),
                .init(title: "Ready", value: viewModel.hasRequiredPermissions ? "Yes" : "Needs attention", systemImage: "checkmark.circle.fill", tint: viewModel.hasRequiredPermissions ? .green : .orange),
            ]
        case .shortcut:
            return [
                .init(title: "Shortcut", value: viewModel.shortcutSummaryText, systemImage: "keyboard", tint: .pink),
                .init(title: "Press", value: viewModel.shortcutTestDetectedPress ? "Detected" : "Waiting", systemImage: "pointer", tint: .blue),
                .init(title: "Round trip", value: viewModel.shortcutTestCompletedRoundTrip ? "Complete" : "Pending", systemImage: "arrow.triangle.2.circlepath", tint: .green),
            ]
        case .firstSuccess:
            return [
                .init(title: "Result", value: viewModel.firstSuccessPreviewText ?? "No preview yet", systemImage: "text.quote", tint: .mint),
                .init(title: "Gate", value: viewModel.canContinueFirstSuccessOnboarding ? "Open" : "Waiting", systemImage: "checkmark.circle", tint: .green),
                .init(title: "Fallback", value: viewModel.canSkipFirstSuccessOnboarding ? "Skip allowed" : "Required", systemImage: "arrow.right.circle", tint: .orange),
            ]
        case .done:
            return [
                .init(title: "Shortcut", value: viewModel.shortcutSummaryText, systemImage: "keyboard", tint: .purple),
                .init(title: "Mode", value: viewModel.onboardingMode == .apiKey ? "API Key" : "Logged In", systemImage: "arrow.triangle.branch", tint: .blue),
                .init(title: "Permissions", value: viewModel.hasRequiredPermissions ? "Enabled" : "Check required", systemImage: "shield.checkerboard", tint: .green),
            ]
        }
    }
}

private struct OnboardingVisualMetric: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let systemImage: String
    let tint: Color
}

#endif
