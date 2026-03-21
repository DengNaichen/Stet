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
                        Button(viewModel.microphonePermissionActionTitle) {
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
                            Button("Grant Permission") {
                                viewModel.requestAutoPasteAccess()
                            }

                            Button("Open System Settings") {
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

                Button("Continue") {
                    viewModel.continueOnboarding()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.hasRequiredPermissions)
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
