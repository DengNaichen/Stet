#if os(macOS)
    import Combine
    import Foundation
    import Observation

    /// Presentation facade over the shared audio input device selection.
    @MainActor
    @Observable
    final class AudioInputDeviceListViewModel {
        private let deviceManager: AudioDeviceSelectionManager
        @ObservationIgnored private var cancellables = Set<AnyCancellable>()

        init(deviceManager: AudioDeviceSelectionManager = .shared) {
            self.deviceManager = deviceManager
            selectedDevice = deviceManager.selectedDevice
            externalDevices = deviceManager.availableDevices.filter { !$0.isBuiltIn }
            deviceManager.$selectedDevice
                .sink { [weak self] in self?.selectedDevice = $0 }
                .store(in: &cancellables)
            deviceManager.$availableDevices
                .sink { [weak self] in self?.externalDevices = $0.filter { !$0.isBuiltIn } }
                .store(in: &cancellables)
        }

        private(set) var selectedDevice: AudioHardwareDevice?
        private(set) var externalDevices: [AudioHardwareDevice]

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
