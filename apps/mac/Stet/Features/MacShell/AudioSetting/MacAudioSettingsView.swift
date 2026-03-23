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
        .padding(.horizontal, 20)
        .padding(.bottom, 28)
        .task {
            viewModel.onAppear()
        }
        .onDisappear {
            viewModel.onDisappear()
        }
    }
}
#endif
