#if os(macOS)
    import Foundation
    import Combine
    import ApplicationServices
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
                VStack(spacing: 12) {
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

                    // Row 2: Command (R), Option (R), Arrows
                    HStack(alignment: .bottom, spacing: 10) {
                        Spacer(minLength: 40)
                        KeyCap(
                            text: "command", subtext: "⌘", icon: nil, width: 70,
                            isPressed: keyboardMonitor.modifierFlags.contains(.maskCommand))
                        KeyCap(
                            text: "option", subtext: "⌥", icon: nil, width: 60,
                            isPressed: keyboardMonitor.modifierFlags.contains(.maskAlternate))

                        HStack(alignment: .bottom, spacing: 4) {
                            KeyCap(
                                text: "", subtext: nil, icon: "chevron.left", width: 44, height: 26,
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
                                height: 26, isPressed: keyboardMonitor.pressedKeys.contains(124))
                        }
                    }
                }
                .padding(40)
                .background(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .fill(Color(nsColor: .windowBackgroundColor).opacity(0.3))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                )

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
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 6)
                        .padding(.top, 4)
                }

                if let subtext {
                    Text(subtext)
                        .font(.system(size: 10))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 6)
                        .padding(.top, 4)
                }

                Spacer(minLength: 0)

                Text(text)
                    .font(.system(size: 13, weight: .regular))
                    .frame(
                        maxWidth: .infinity,
                        alignment: icon != nil || subtext != nil ? .leading : .center
                    )
                    .padding(.leading, icon != nil || subtext != nil ? 6 : 0)
                    .padding(.bottom, 6)
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

        var body: some View {
            ZStack {
                backgroundGradient

                if step == .shortcut {
                    OnboardingKeyboardView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                return "Say something in the box"
            case .done:
                return "Ready to go"
            }
        }

        private var panelSubtitle: String {
            switch step {
            case .mode:
                return "Managed login and BYOK still lead to the same next steps."
            case .apiKey:
                return "Choose a provider, enter a key, and continue once it validates."
            case .login:
                return "Use Google, GitHub, or email to finish the managed path."
            case .permissions:
                return "Mic and input control remain the only permissions Stet needs."
            case .shortcut:
                return "Choose the shortcut you want to use."
            case .firstSuccess:
                return "Click the text box, then use your hotkey to speak a sentence."
            case .done:
                return "Everything needed for the onboarding path is now in place."
            }
        }

        private var heroTitle: String {
            switch step {
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
                return "The shortcut is ready to use."
            case .firstSuccess:
                return viewModel.canContinueFirstSuccessOnboarding
                    ? "A successful result is visible in the box."
                    : "Speak naturally and let the first pass finish."
            case .done:
                return "The onboarding path is complete and the app is ready to use."
            }
        }

        private var footerTitle: String {
            switch step {
            case .mode:
                return "No branching complexity"
            case .apiKey:
                return "Provider-aware"
            case .login:
                return "Managed services enabled"
            case .permissions:
                return "Use only what is needed"
            case .shortcut:
                return "Shortcut setup"
            case .firstSuccess:
                return "Live input check"
            case .done:
                return "Start dictating anywhere"
            }
        }

        private var footerSubtitle: String {
            switch step {
            case .mode:
                return "Your choice only determines which existing step comes next."
            case .apiKey:
                return "This path still saves and validates the provider key before advancing."
            case .login:
                return "A successful sign-in still leads straight through the existing flow."
            case .permissions:
                return "Permission checks remain exactly where the app expects them."
            case .shortcut:
                return "The recorder is all you need here."
            case .firstSuccess:
                return "This step now exercises a real text target."
            case .done:
                return "Finish the flow and begin using the app immediately."
            }
        }

        private var accentColor: Color {
            switch step {
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
            case .mode:
                return [
                    .init(
                        title: "BYOK", value: "Your provider", systemImage: "key.fill",
                        tint: .orange),
                    .init(
                        title: "Managed", value: "Login flow",
                        systemImage: "person.crop.circle.badge.checkmark", tint: .indigo),
                    .init(
                        title: "Next", value: "Permissions", systemImage: "arrow.right.circle.fill",
                        tint: .green),
                ]
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
            case .login:
                return [
                    .init(
                        title: "Session", value: viewModel.relaySessionEmail ?? "Not signed in",
                        systemImage: "person.text.rectangle", tint: .indigo),
                    .init(
                        title: "Providers", value: "Google, GitHub, Email",
                        systemImage: "person.2.fill", tint: .blue),
                    .init(
                        title: "Continue", value: "Managed flow",
                        systemImage: "arrow.right.circle.fill", tint: .green),
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
