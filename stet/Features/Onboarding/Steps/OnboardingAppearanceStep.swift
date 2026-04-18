#if os(macOS)
    import StetVisuals
    import SwiftUI

    struct OnboardingAppearanceStep: View {
        @ObservedObject var viewModel: OnboardingViewModel
        @ObservedObject var appearanceViewModel: MacAppearanceSettingsViewModel

        var body: some View {
            VStack(alignment: .leading, spacing: 18) {
                Text("Browse themes on the right. The capsule shows a live preview.")
                    .font(.body)
                    .foregroundStyle(.secondary)

                Spacer()

                MacDictationCapsulePreviewView(
                    theme: MacDictationShaderTheme(rawValue: viewModel.onboardingPreviewTheme.rawValue) ?? .egg,
                    scale: 2.5
                )
                .frame(maxWidth: .infinity, alignment: .center)

                Spacer()

                HStack {
                    OnboardingBackButton { viewModel.retreatOnboarding() }

                    Spacer()

                    OnboardingActionButton(
                        title: "Apply & Finish",
                        minHeight: 48
                    ) {
                        viewModel.applyOnboardingAppearanceTheme()
                        viewModel.finishOnboarding()
                    }
                }
            }
        }
    }

    #if DEBUG
        #Preview {
            OnboardingAppearanceStep(
                viewModel: OnboardingViewModel(
                    coordinator: MockOnboardingCoordinator(step: .appearance)
                ),
                appearanceViewModel: .shared
            )
            .frame(width: 440)
            .padding()
        }
    #endif

#endif
