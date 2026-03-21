#if os(macOS)
protocol AudioDeviceProviding: Sendable {
    func allInputDevices() -> [AudioHardwareDevice]
    func defaultInputDevice() -> AudioHardwareDevice?
}

struct SystemAudioDeviceProvider: AudioDeviceProviding {
    func allInputDevices() -> [AudioHardwareDevice] {
        AudioInputDeviceManager.allInputDevices()
    }

    func defaultInputDevice() -> AudioHardwareDevice? {
        AudioInputDeviceManager.defaultInputDevice()
    }
}
#endif
