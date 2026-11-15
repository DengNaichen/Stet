#if os(macOS)
    import SwiftUI

    struct AudioInputDeviceMenuSection: View {
        let deviceList: AudioInputDeviceListViewModel

        var body: some View {
            Group {
                Button {
                    deviceList.selectBuiltInDefault()
                } label: {
                    menuRow(
                        Text("Default (Built-in Microphone)"),
                        isSelected: deviceList.selectedDevice?.isBuiltIn ?? true
                    )
                }

                ForEach(externalDevices, id: \.uid) { device in
                    Button {
                        deviceList.selectDevice(device)
                    } label: {
                        menuRow(
                            Text(verbatim: device.name),
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

        private func menuRow(_ label: Text, isSelected: Bool) -> some View {
            HStack {
                label
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                }
            }
        }
    }
#endif
