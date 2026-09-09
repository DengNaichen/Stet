#if os(macOS)
    import SwiftUI

    struct MacMicrophoneSettingsView: View {
        @StateObject private var viewModel = MacAudioSettingsViewModel()

        var body: some View {
            Form {
                AudioInputDeviceSettingsSection(
                    deviceManager: viewModel.deviceManager,
                    microphoneTestViewModel: viewModel.microphoneTestViewModel
                )
            }
            .formStyle(.grouped)
            .scrollIndicators(.never)
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
