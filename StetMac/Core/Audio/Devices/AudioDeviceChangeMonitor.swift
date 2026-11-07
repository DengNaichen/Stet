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

        private var propertyListenerBlock: AudioObjectPropertyListenerBlock?
        private var monitorClientCount = 0
        private var isMonitoring = false

        init() {}

        func startMonitoring() {
            monitorClientCount += 1
            let shouldRegister = !isMonitoring

            guard shouldRegister else {
                return
            }

            var propertyAddress = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDevices,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )

            let listenerBlock: AudioObjectPropertyListenerBlock = { _, _ in
                MainActor.assumeIsolated {
                    NotificationCenter.default.post(
                        name: AudioDeviceChangeMonitor.devicesDidChangeNotification,
                        object: nil
                    )
                }
            }

            propertyListenerBlock = listenerBlock

            let status = AudioObjectAddPropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &propertyAddress,
                DispatchQueue.main,
                listenerBlock
            )

            if status == noErr {
                isMonitoring = true
                Self.logger.info("AudioDeviceChangeMonitor: Started monitoring device changes")
            } else {
                monitorClientCount = max(0, monitorClientCount - 1)
                Self.logger.warning("AudioDeviceChangeMonitor: Failed to register property listener. status=\(status)")
                propertyListenerBlock = nil
            }
        }

        func stopMonitoring() {
            if monitorClientCount > 0 {
                monitorClientCount -= 1
            }
            let shouldUnregister = monitorClientCount == 0 && isMonitoring
            let listenerBlock = propertyListenerBlock

            guard shouldUnregister, let listenerBlock else {
                return
            }

            var propertyAddress = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDevices,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )

            let status = AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &propertyAddress,
                DispatchQueue.main,
                listenerBlock
            )

            if status == noErr {
                Self.logger.info("AudioDeviceChangeMonitor: Stopped monitoring device changes")
            } else {
                Self.logger.warning(
                    "AudioDeviceChangeMonitor: Failed to unregister property listener. status=\(status)")
            }

            propertyListenerBlock = nil
            isMonitoring = false
        }

        isolated deinit {
            monitorClientCount = 1
            stopMonitoring()
        }
    }
#endif
