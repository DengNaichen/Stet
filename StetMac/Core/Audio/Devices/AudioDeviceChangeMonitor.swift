#if os(macOS)
    import CoreAudio
    import Foundation
    import os

    @MainActor
    final class AudioDeviceChangeMonitor {
        static let shared = AudioDeviceChangeMonitor()
        static let devicesDidChangeNotification = Notification.Name("AudioDevicesDidChange")

        private static let logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "com.openwhispr.Stet",
            category: "AudioDeviceMonitor"
        )

        // Own the wrapper: mutating shared.delegates would interfere with other listeners.
        private let system: AudioHardwareSystem
        private let notificationCenter: NotificationCenter
        private let properties = [PropertyAddress(kAudioHardwarePropertyDevices)]
        private var monitorClientCount = 0
        private var isMonitoring = false

        init(
            system: AudioHardwareSystem = AudioHardwareSystem(id: AudioObjectID(kAudioObjectSystemObject)),
            notificationCenter: NotificationCenter = .default
        ) {
            self.system = system
            self.notificationCenter = notificationCenter
        }

        func startMonitoring() {
            monitorClientCount += 1
            guard !isMonitoring else { return }

            system.delegates = [
                DeviceListListener { [weak self] in
                    guard let self, self.isMonitoring, self.monitorClientCount > 0 else { return }
                    self.notificationCenter.post(name: Self.devicesDidChangeNotification, object: nil)
                }
            ]
            do {
                try system.addListener(forProperties: properties, dispatchQueue: .main)
                isMonitoring = true
                Self.logger.info("AudioDeviceChangeMonitor: Started monitoring device changes")
            } catch {
                monitorClientCount = max(0, monitorClientCount - 1)
                system.delegates = []
                Self.logger.warning("AudioDeviceChangeMonitor: Failed to register property listener. error=\(error)")
            }
        }

        func stopMonitoring() {
            if monitorClientCount > 0 { monitorClientCount -= 1 }
            guard monitorClientCount == 0, isMonitoring else { return }

            do {
                try system.removeListener(forProperties: properties, dispatchQueue: .main)
                system.delegates = []
                isMonitoring = false
                Self.logger.info("AudioDeviceChangeMonitor: Stopped monitoring device changes")
            } catch {
                // Keep the registration so a later stop can retry without adding a duplicate.
                Self.logger.warning("AudioDeviceChangeMonitor: Failed to unregister property listener. error=\(error)")
            }
        }

        isolated deinit {
            monitorClientCount = 1
            stopMonitoring()
            system.delegates = []
        }
    }

    private nonisolated final class DeviceListListener: PropertyListenerDelegate {
        private let onChange: @MainActor @Sendable () -> Void

        init(onChange: @escaping @MainActor @Sendable () -> Void) {
            self.onChange = onChange
        }

        func propertiesChanged(properties: [AudioObjectPropertyAddress]) {
            // Device-list listeners are registered and removed on DispatchQueue.main.
            MainActor.assumeIsolated { onChange() }
        }
    }
#endif
