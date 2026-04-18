#if os(macOS)
    import SwiftUI

    struct MacAudioSettingsView: View {
        @StateObject private var viewModel = MacAudioSettingsViewModel()

        var body: some View {
            Form {
                AudioInputDeviceSettingsSection(
                    deviceManager: viewModel.deviceManager,
                    microphoneTestViewModel: viewModel.microphoneTestViewModel
                )
            }
            .formStyle(.grouped)
            .padding(.leading, MacUI.SettingsViewMetrics.formHorizontalPadding)
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
