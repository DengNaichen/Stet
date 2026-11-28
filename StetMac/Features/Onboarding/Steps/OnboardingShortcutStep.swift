#if os(macOS)
    import KeyboardShortcuts
    import SwiftUI

    struct OnboardingShortcutStep: View {
        @ObservedObject var viewModel: OnboardingViewModel
        @StateObject private var keyboardMonitor = OnboardingKeyboardMonitor()
        @State private var currentShortcut: KeyboardShortcuts.Shortcut? = KeyboardShortcuts.getShortcut(
            for: HotkeyBinding.dictation.name
        )
        @State private var hasDetectedPress = false

        var body: some View {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 18) {
                    OnboardingStepHeader(
                        eyebrow: "Step 3 of 5",
                        title: "Set your speaking shortcut",
                        subtitle: "Press it once to test how it feels, or record a combination you prefer."
                    )

                    VStack(spacing: 0) {
                        VStack(spacing: 18) {
                            OnboardingShortcutKeycapsView(
                                shortcut: currentShortcut,
                                monitor: keyboardMonitor
                            )

                            statusLine
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 24)

                        LinearHairlineDivider()

                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Change shortcut")
                                    .font(.system(size: 12.5, weight: .medium))
                                    .foregroundStyle(MacUI.Foreground.primary)

                                Text("Use a modifier-plus-key combination.")
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(MacUI.Foreground.secondary)
                            }

                            Spacer(minLength: 8)

                            KeyboardShortcuts.Recorder(for: HotkeyBinding.dictation.name) { shortcut in
                                AnalyticsService.track("hotkey_changed")
                                currentShortcut = shortcut
                                hasDetectedPress = false
                                viewModel.updateShortcutSummary(shortcut)
                            }
                            .frame(width: 170, alignment: .trailing)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(MacUI.LinearSurfaces.subtleHover)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(MacUI.LinearSurfaces.card)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .strokeBorder(MacUI.LinearSurfaces.hairline, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                }
                .padding(.horizontal, OnboardingMetrics.contentHorizontalPadding)
                .padding(.top, 4)
                .padding(.bottom, 16)

                OnboardingFooterBar {
                    OnboardingBackButton {
                        viewModel.retreatOnboarding()
                    }
                } trailing: {
                    OnboardingPrimaryButton("Continue") {
                        viewModel.continueOnboarding()
                    }
                }
            }
            .onAppear {
                currentShortcut = KeyboardShortcuts.getShortcut(for: HotkeyBinding.dictation.name)
                viewModel.updateShortcutSummary(currentShortcut)
                keyboardMonitor.start()
            }
            .onDisappear {
                keyboardMonitor.stop()
            }
            .onChange(of: keyboardMonitor.pressedKeys) { _, _ in
                checkShortcutMatch()
            }
            .onChange(of: keyboardMonitor.modifierFlags) { _, _ in
                checkShortcutMatch()
            }
        }

        @ViewBuilder
        private var statusLine: some View {
            if hasDetectedPress {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                    Text("Shortcut detected — ready to speak!")
                        .font(.system(size: 12.5, weight: .medium))
                }
                .foregroundStyle(MacUI.Foreground.success)
                .transition(.opacity)
            } else {
                Text(
                    "Try pressing \(OnboardingShortcutKeySpec.formattedString(for: currentShortcut)) on your keyboard"
                )
                .font(.system(size: 12.5))
                .foregroundStyle(MacUI.Foreground.secondary)
            }
        }

        private func checkShortcutMatch() {
            guard let shortcut = currentShortcut, !hasDetectedPress else { return }
            if keyboardMonitor.isShortcutActive(shortcut) {
                withAnimation(.easeOut(duration: 0.18)) {
                    hasDetectedPress = true
                }
            }
        }
    }

    #if DEBUG
        #Preview {
            OnboardingShortcutStep(
                viewModel: OnboardingViewModel(coordinator: MockOnboardingCoordinator(step: .shortcut))
            )
            .frame(width: OnboardingMetrics.windowWidth, height: 500)
        }
    #endif
#endif
