#if os(macOS)
    import SwiftUI

    struct MacMicrophoneSettingsView: View {
        @StateObject private var viewModel = MacAudioSettingsViewModel()

        var body: some View {
            LinearPageContainer(title: "Microphone") {
                AudioInputDeviceSettingsSection(
                    deviceList: viewModel.deviceList,
                    microphoneTestViewModel: viewModel.microphoneTestViewModel
                )
            }
            .task {
                viewModel.onAppear()
            }
            .onDisappear {
                viewModel.onDisappear()
            }
        }
    }
#endif
