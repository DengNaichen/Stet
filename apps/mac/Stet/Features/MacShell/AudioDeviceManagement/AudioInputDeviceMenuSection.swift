#if os(macOS)
import SwiftUI

struct AudioInputDeviceMenuSection: View {
    @ObservedObject private var deviceManager: AudioDeviceSelectionManager

    @MainActor
    init(deviceManager: AudioDeviceSelectionManager? = nil) {
        self._deviceManager = ObservedObject(wrappedValue: deviceManager ?? .shared)
    }

    var body: some View {
        Section("Audio Input Device") {
            Button {
                deviceManager.resetToAutomatic()
            } label: {
                menuRow(
                    title: "Default (Built-in Microphone)",
                    isSelected: deviceManager.strategy == .automatic
                )
            }

            ForEach(deviceManager.availableDevices, id: \.uid) { device in
                Button {
                    deviceManager.selectDevice(device)
                } label: {
                    menuRow(
                        title: device.name,
                        isSelected: deviceManager.strategy == .manual &&
                            device.uid == deviceManager.selectedDevice?.uid
                    )
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AudioDeviceChangeMonitor.devicesDidChangeNotification)) { _ in
            deviceManager.refreshDevices()
        }
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
