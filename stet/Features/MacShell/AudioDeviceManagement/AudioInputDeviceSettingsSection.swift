#if os(macOS)
    import SwiftUI

    struct AudioInputDeviceSettingsSection: View {
        @ObservedObject var deviceManager: AudioDeviceSelectionManager
        @ObservedObject var microphoneTestViewModel: MicrophoneTestViewModel

        var body: some View {
            Section("Audio Input Device") {
                Picker("Microphone", selection: microphoneSelectionBinding) {
                    Text("Default (Built-in Microphone)")
                        .tag(nil as String?)

                    ForEach(externalDevices, id: \.uid) { device in
                        Text(device.name)
                            .tag(device.uid as String?)
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
            .onReceive(NotificationCenter.default.publisher(for: AudioDeviceChangeMonitor.devicesDidChangeNotification))
            { _ in
                deviceManager.refreshDevices()
            }
        }

        private var microphoneSelectionBinding: Binding<String?> {
            Binding(
                get: { selectedMicrophoneSelection },
                set: { newValue in
                    applyMicrophoneSelection(newValue)
                }
            )
        }

        private var externalDevices: [AudioHardwareDevice] {
            deviceManager.availableDevices.filter { !$0.isBuiltIn }
        }

        private var selectedMicrophoneSelection: String? {
            guard let selected = deviceManager.selectedDevice else {
                return nil
            }

            return selected.isBuiltIn ? nil : selected.uid
        }

        private func applyMicrophoneSelection(_ uid: String?) {
            guard let uid else {
                deviceManager.selectBuiltInDefault()
                return
            }

            if let device = externalDevices.first(where: { $0.uid == uid }) {
                deviceManager.selectDevice(device)
            }
        }
    }
#endif
