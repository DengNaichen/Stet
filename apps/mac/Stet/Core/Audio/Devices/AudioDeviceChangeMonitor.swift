#if os(macOS)
import CoreAudio
import Foundation

final class AudioDeviceChangeMonitor {
    static let shared = AudioDeviceChangeMonitor()
    static let devicesDidChangeNotification = Notification.Name("AudioDevicesDidChange")

    private let stateLock = NSLock()
    private var propertyListenerBlock: AudioObjectPropertyListenerBlock?
    private var monitorClientCount = 0
    private var isMonitoring = false

    init() {}

    func startMonitoring() {
        stateLock.lock()
        monitorClientCount += 1
        let shouldRegister = !isMonitoring
        stateLock.unlock()

        guard shouldRegister else {
            return
        }

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let listenerBlock: AudioObjectPropertyListenerBlock = { _, _ in
            DispatchQueue.main.async {
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
            stateLock.lock()
            isMonitoring = true
            stateLock.unlock()
            AppLogger.info("AudioDeviceChangeMonitor: Started monitoring device changes")
        } else {
            stateLock.lock()
            monitorClientCount = max(0, monitorClientCount - 1)
            AppLogger.warning("AudioDeviceChangeMonitor: Failed to register property listener. status=\(status)")
            propertyListenerBlock = nil
            stateLock.unlock()
        }
    }

    func stopMonitoring() {
        stateLock.lock()
        if monitorClientCount > 0 {
            monitorClientCount -= 1
        }
        let shouldUnregister = monitorClientCount == 0 && isMonitoring
        let listenerBlock = propertyListenerBlock
        stateLock.unlock()

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
            AppLogger.info("AudioDeviceChangeMonitor: Stopped monitoring device changes")
        } else {
            AppLogger.warning("AudioDeviceChangeMonitor: Failed to unregister property listener. status=\(status)")
        }

        stateLock.lock()
        propertyListenerBlock = nil
        isMonitoring = false
        stateLock.unlock()
    }

    deinit {
        stopMonitoring()
    }
}
#endif
