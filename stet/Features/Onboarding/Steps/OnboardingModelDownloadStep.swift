#if os(macOS)
    import SwiftUI

    struct OnboardingModelDownloadStep: View {
        @ObservedObject var viewModel: OnboardingViewModel

        var body: some View {
            VStack(spacing: 24) {
                Spacer()
                
                OnboardingActionButton(
                    title: viewModel.localWhisperDownloadPrimaryButtonTitle,
                    isEnabled: viewModel.canContinueLocalWhisperDownload || viewModel.localWhisperDownloadState == .idle || viewModel.isLocalWhisperDownloadFailed, 
                    minHeight: 52,
                    isCentered: true
                ) {
                    Task {
                        await viewModel.handleLocalWhisperDownloadPrimaryAction()
                    }
                }
            }
            .padding(.bottom, 40)
        }



    }

    #if DEBUG
        #Preview {
            OnboardingModelDownloadStep(
                viewModel: OnboardingViewModel(coordinator: MockOnboardingCoordinator(step: .download))
            )
            .frame(width: 440)
            .padding()
        }
    #endif

#endif
