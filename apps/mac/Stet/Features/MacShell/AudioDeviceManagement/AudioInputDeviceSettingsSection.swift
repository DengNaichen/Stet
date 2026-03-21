#if os(macOS)
import SwiftUI

struct AudioInputDeviceSettingsSection: View {
    @ObservedObject var deviceManager: AudioDeviceSelectionManager
    @StateObject private var microphoneTestViewModel: MicrophoneTestViewModel

    init(deviceManager: AudioDeviceSelectionManager) {
        self.deviceManager = deviceManager
        self._microphoneTestViewModel = StateObject(
            wrappedValue: MicrophoneTestViewModel(
                microphoneTestService: DefaultMicrophoneTestService.shared
            )
        )
    }

    var body: some View {
        Section("Audio Input Device") {
            Picker("Selection Strategy", selection: selectionStrategyBinding) {
                Text("Default (Built-in Microphone)")
                    .tag(AudioDeviceSelectionManager.SelectionStrategy.automatic)
                Text("Manual Selection")
                    .tag(AudioDeviceSelectionManager.SelectionStrategy.manual)
            }

            if deviceManager.strategy == .manual {
                Picker("Microphone", selection: preferredDeviceUIDBinding) {
                    Text("Select a microphone...")
                        .tag(nil as String?)

                    ForEach(deviceManager.availableDevices, id: \.uid) { device in
                        Text(device.name)
                            .tag(device.uid as String?)
                    }
                }
            }

            if let selected = deviceManager.selectedDevice {
                HStack {
                    Text("Current Device:")
                    Spacer()
                    Text(selected.name)
                        .foregroundStyle(.secondary)
                }
            }

            MicrophoneTestView(viewModel: microphoneTestViewModel)
        }
        .onAppear {
            AudioDeviceChangeMonitor.shared.startMonitoring()
        }
        .onDisappear {
            AudioDeviceChangeMonitor.shared.stopMonitoring()
        }
        .onReceive(NotificationCenter.default.publisher(for: AudioDeviceChangeMonitor.devicesDidChangeNotification)) { _ in
            deviceManager.refreshDevices()
        }
    }

    private var selectionStrategyBinding: Binding<AudioDeviceSelectionManager.SelectionStrategy> {
        Binding(
            get: { deviceManager.strategy },
            set: { newValue in
                applySelectionStrategy(newValue)
            }
        )
    }

    private var preferredDeviceUIDBinding: Binding<String?> {
        Binding(
            get: { deviceManager.preferredDeviceUID },
            set: { newValue in
                applyPreferredDeviceUID(newValue)
            }
        )
    }

    private func applySelectionStrategy(_ strategy: AudioDeviceSelectionManager.SelectionStrategy) {
        guard deviceManager.strategy != strategy else { return }

        switch strategy {
        case .automatic:
            deviceManager.resetToAutomatic()
        case .manual:
            deviceManager.strategy = .manual
            deviceManager.refreshDevices()
        }
    }

    private func applyPreferredDeviceUID(_ uid: String?) {
        if let uid,
           let device = deviceManager.availableDevices.first(where: { $0.uid == uid }) {
            deviceManager.selectDevice(device)
            return
        }

        deviceManager.preferredDeviceUID = uid
        deviceManager.refreshDevices()
    }
}
#endif
