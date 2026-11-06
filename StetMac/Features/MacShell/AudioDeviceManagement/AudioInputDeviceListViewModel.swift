#if os(macOS)
    import Combine
    import Foundation

    /// Presentation facade over the shared audio input device selection.
    @MainActor
    final class AudioInputDeviceListViewModel: ObservableObject {
        private let deviceManager: AudioDeviceSelectionManager
        private var cancellable: AnyCancellable?

        init(deviceManager: AudioDeviceSelectionManager = .shared) {
            self.deviceManager = deviceManager
            cancellable = deviceManager.objectWillChange
                .sink { [weak self] _ in
                    self?.objectWillChange.send()
                }
        }

        var selectedDevice: AudioHardwareDevice? { deviceManager.selectedDevice }

        var externalDevices: [AudioHardwareDevice] {
            deviceManager.availableDevices.filter { !$0.isBuiltIn }
        }

        /// Refreshes the device list and keeps it current while a device UI is visible.
        func startMonitoring() {
            deviceManager.refreshDevices()
            AudioDeviceChangeMonitor.shared.startMonitoring()
        }

        func stopMonitoring() {
            AudioDeviceChangeMonitor.shared.stopMonitoring()
        }

        func refreshDevices() {
            deviceManager.refreshDevices()
        }

        func selectDevice(_ device: AudioHardwareDevice) {
            deviceManager.selectDevice(device)
        }

        func selectBuiltInDefault() {
            deviceManager.selectBuiltInDefault()
        }
    }
#endif
