#if os(macOS)
    import SwiftUI

    struct MacSpeechAndRefineSettingsView: View {
        @ObservedObject var openAIViewModel: MacOpenAISettingsViewModel
        var scrollTarget: MacSettingsTargetSection? = nil
        var scrollTrigger: Int = 0

        @StateObject private var audioViewModel = MacAudioSettingsViewModel()

        var body: some View {
            LinearPageContainer(
                title: "Speech & Refine",
                scrollTarget: scrollTarget,
                scrollTrigger: scrollTrigger
            ) {
                VStack(alignment: .leading, spacing: MacUI.LinearMetrics.contentSectionSpacing) {
                    MacTranscriptionSettingsSections(viewModel: audioViewModel)
                }
                .id(MacSettingsTargetSection.onDeviceTranscription)

                LinearHairlineDivider()
                    .padding(.vertical, 2)

                MacRefineSettingsSections(viewModel: openAIViewModel)
                    .id(MacSettingsTargetSection.aiRefine)
            }
            .task {
                audioViewModel.onAppear()
                openAIViewModel.load()
            }
            .onDisappear {
                audioViewModel.onDisappear()
            }
        }
    }
#endif
