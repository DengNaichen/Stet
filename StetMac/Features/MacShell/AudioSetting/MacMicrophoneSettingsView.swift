#if os(macOS)
    import SwiftUI

    struct MacMicrophoneSettingsView: View {
        @StateObject private var viewModel = MacAudioSettingsViewModel()

        var body: some View {
            Form {
                AudioInputDeviceSettingsSection(
                    deviceList: viewModel.deviceList,
                    microphoneTestViewModel: viewModel.microphoneTestViewModel
                )
            }
            .macSettingsFormStyle()
            .padding(.bottom, MacUI.SettingsViewMetrics.formBottomPadding)
            .task {
                viewModel.onAppear()
            }
            .onDisappear {
                viewModel.onDisappear()
            }
        }
    }
#endif
