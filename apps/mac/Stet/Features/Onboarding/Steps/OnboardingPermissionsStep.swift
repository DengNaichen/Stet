#if os(macOS)
import SwiftUI

struct OnboardingPermissionsStep: View {
    @ObservedObject var viewModel: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    PermissionGateRow(
                        title: "Microphone",
                        description: "Used to receive voice input",
                        statusText: viewModel.microphoneAccessStatusText,
                        tint: viewModel.microphoneAccessNeedsAttention ? .orange : .green
                    ) {
                        OnboardingActionButton(
                            title: viewModel.microphonePermissionActionTitle,
                            systemImage: "mic.fill",
                            background: Color.white.opacity(0.08),
                            foreground: .primary,
                            strokeColor: Color.white.opacity(0.10),
                            minHeight: 44
                        ) {
                            viewModel.resolveMicrophoneAccess()
                        }
                    }

                    PermissionGateRow(
                        title: "Accessibility / Input Control",
                        description: "Used to insert text into active apps",
                        statusText: viewModel.autoPasteStatusText,
                        tint: viewModel.autoPasteAccessNeedsAttention ? .orange : .green
                    ) {
                        HStack(spacing: 8) {
                            OnboardingActionButton(
                                title: "Grant Permission",
                                systemImage: "checkmark.shield",
                                background: Color.white.opacity(0.08),
                                foreground: .primary,
                                strokeColor: Color.white.opacity(0.10),
                                minHeight: 44
                            ) {
                                viewModel.requestAutoPasteAccess()
                            }

                            OnboardingActionButton(
                                title: "Open System Settings",
                                systemImage: "gearshape",
                                background: Color.white.opacity(0.08),
                                foreground: .primary,
                                strokeColor: Color.white.opacity(0.10),
                                minHeight: 44
                            ) {
                                viewModel.openAccessibilitySettings()
                            }
                        }
                    }

                    if viewModel.microphoneAccessNeedsAttention || viewModel.autoPasteAccessNeedsAttention {
                        MessageBanner(
                            text: "Permissions not yet detected. Please authorize in System Settings and return.",
                            role: .warning
                        )
                    }
                }
                .padding(8)
            }

            Spacer()

            HStack {
                if viewModel.onboardingMode != nil {
                    Button("Back") {
                        viewModel.retreatOnboarding()
                    }
                }

                Spacer()

                OnboardingActionButton(
                    title: "Continue",
                    isEnabled: viewModel.hasRequiredPermissions,
                    minHeight: 48
                ) {
                    viewModel.continueOnboarding()
                }
            }
        }
    }
}

#if DEBUG
#Preview {
    OnboardingPermissionsStep(viewModel: OnboardingViewModel(coordinator: MockOnboardingCoordinator(step: .permissions)))
        .frame(width: 440)
        .padding()
}
#endif

#endif
