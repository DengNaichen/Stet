#if os(macOS)
    import SwiftUI

    struct OnboardingShortcutStep: View {
        @ObservedObject var viewModel: OnboardingViewModel

        var body: some View {
            VStack(alignment: .leading, spacing: 18) {
                GroupBox("Set Shortcut") {
                    VStack(alignment: .leading, spacing: 14) {
                        MacHotKeySettingsSectionView(hotkey: .dictation) { shortcut in
                            viewModel.updateShortcutSummary(shortcut)
                        }
                    }
                    .padding(8)
                }

                Text("We've set Command + . as your default shortcut. Try pressing it now to see it in action.")
                    .font(.body)
                    .foregroundStyle(.secondary)

                Spacer()

                HStack {
                    Button("Back") {
                        viewModel.retreatOnboarding()
                    }

                    Spacer()

                    OnboardingActionButton(
                        title: "Continue",
                        isEnabled: true,
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
            OnboardingShortcutStep(
                viewModel: OnboardingViewModel(coordinator: MockOnboardingCoordinator(step: .shortcut))
            )
            .frame(width: 440)
            .padding()
        }
    #endif

#endif
