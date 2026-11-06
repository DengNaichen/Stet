#if os(macOS)
    import SwiftUI

    struct AudioInputDeviceSettingsSection: View {
        @ObservedObject var deviceList: AudioInputDeviceListViewModel
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
                deviceList.startMonitoring()
            }
            .onDisappear {
                deviceList.stopMonitoring()
            }
            .onReceive(NotificationCenter.default.publisher(for: AudioDeviceChangeMonitor.devicesDidChangeNotification))
            { _ in
                deviceList.refreshDevices()
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
            deviceList.externalDevices
        }

        private var selectedMicrophoneSelection: String? {
            guard let selected = deviceList.selectedDevice else {
                return nil
            }

            return selected.isBuiltIn ? nil : selected.uid
        }

        private func applyMicrophoneSelection(_ uid: String?) {
            guard let uid else {
                deviceList.selectBuiltInDefault()
                return
            }

            if let device = externalDevices.first(where: { $0.uid == uid }) {
                deviceList.selectDevice(device)
            }
        }
    }
#endif
