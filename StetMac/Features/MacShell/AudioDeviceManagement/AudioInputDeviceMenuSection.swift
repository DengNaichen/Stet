#if os(macOS)
    import SwiftUI

    struct AudioInputDeviceMenuSection: View {
        @StateObject private var deviceList = AudioInputDeviceListViewModel()

        var body: some View {
            Group {
                Button {
                    deviceList.selectBuiltInDefault()
                } label: {
                    menuRow(
                        title: "Default (Built-in Microphone)",
                        isSelected: deviceList.selectedDevice?.isBuiltIn ?? true
                    )
                }

                ForEach(externalDevices, id: \.uid) { device in
                    Button {
                        deviceList.selectDevice(device)
                    } label: {
                        menuRow(
                            title: device.name,
                            isSelected: device.uid == deviceList.selectedDevice?.uid
                        )
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: AudioDeviceChangeMonitor.devicesDidChangeNotification))
            { _ in
                deviceList.refreshDevices()
            }
        }

        private var externalDevices: [AudioHardwareDevice] {
            deviceList.externalDevices
        }

        private func menuRow(title: String, isSelected: Bool) -> some View {
            HStack {
                Text(title)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                }
            }
        }
    }
#endif
