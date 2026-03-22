#if os(macOS)
import CoreAudio
import Testing

@testable import Stet

@Suite("Audio Device Selection Resolver")
struct AudioDeviceSelectionResolverTests {
    @Test func builtInDefaultPrefersBuiltInWhenPresent() {
        let builtIn = makeDevice(id: 1, uid: "built-in", name: "MacBook Microphone", transportType: kAudioDeviceTransportTypeBuiltIn)
        let usb = makeDevice(id: 2, uid: "usb", name: "USB Mic", transportType: kAudioDeviceTransportTypeUSB)

        let resolution = AudioDeviceSelectionResolver.resolve(
            availableDevices: [usb, builtIn],
            defaultInputDevice: usb,
            preferredAudioInputDeviceUID: nil
        )

        #expect(resolution.preference == .builtInDefault)
        #expect(resolution.activeDevice == builtIn)
        #expect(!resolution.isUsingFallbackBuiltIn)
    }

    @Test func builtInDefaultFallsBackToSystemDefaultWhenNoBuiltInExists() {
        let usb = makeDevice(id: 2, uid: "usb", name: "USB Mic", transportType: kAudioDeviceTransportTypeUSB)
        let bluetooth = makeDevice(id: 3, uid: "bt", name: "AirPods", transportType: kAudioDeviceTransportTypeBluetooth)

        let resolution = AudioDeviceSelectionResolver.resolve(
            availableDevices: [usb, bluetooth],
            defaultInputDevice: bluetooth,
            preferredAudioInputDeviceUID: nil
        )

        #expect(resolution.preference == .builtInDefault)
        #expect(resolution.activeDevice == bluetooth)
        #expect(!resolution.isUsingFallbackBuiltIn)
    }

    @Test func externalPreferenceUsesMatchingAvailableDevice() {
        let builtIn = makeDevice(id: 1, uid: "built-in", name: "MacBook Microphone", transportType: kAudioDeviceTransportTypeBuiltIn)
        let usb = makeDevice(id: 2, uid: "usb", name: "USB Mic", transportType: kAudioDeviceTransportTypeUSB)

        let resolution = AudioDeviceSelectionResolver.resolve(
            availableDevices: [builtIn, usb],
            defaultInputDevice: builtIn,
            preferredAudioInputDeviceUID: usb.uid
        )

        #expect(resolution.preference == .external(uid: usb.uid))
        #expect(resolution.activeDevice == usb)
        #expect(!resolution.isUsingFallbackBuiltIn)
    }

    @Test func missingExternalPreferenceFallsBackToBuiltIn() {
        let builtIn = makeDevice(id: 1, uid: "built-in", name: "MacBook Microphone", transportType: kAudioDeviceTransportTypeBuiltIn)
        let usb = makeDevice(id: 2, uid: "usb", name: "USB Mic", transportType: kAudioDeviceTransportTypeUSB)

        let resolution = AudioDeviceSelectionResolver.resolve(
            availableDevices: [builtIn],
            defaultInputDevice: builtIn,
            preferredAudioInputDeviceUID: usb.uid
        )

        #expect(resolution.preference == .external(uid: usb.uid))
        #expect(resolution.activeDevice == builtIn)
        #expect(resolution.isUsingFallbackBuiltIn)
    }
}

@MainActor
@Suite("Audio Device Selection Manager")
struct AudioDeviceSelectionManagerTests {
    @Test func currentRecordingDeviceMatchesActiveDevice() {
        let defaults = TestSupport.makeUserDefaults()
        let builtIn = makeDevice(id: 1, uid: "built-in", name: "MacBook Microphone", transportType: kAudioDeviceTransportTypeBuiltIn)
        let usb = makeDevice(id: 2, uid: "usb", name: "USB Mic", transportType: kAudioDeviceTransportTypeUSB)
        let provider = TestAudioDeviceProvider(
            inputDevices: [builtIn, usb],
            defaultInputDevice: usb
        )

        let subject = AudioDeviceSelectionManager(provider: provider, defaults: defaults)

        #expect(subject.preference == .builtInDefault)
        #expect(subject.activeDevice == builtIn)
        #expect(subject.selectedDevice == builtIn)
        #expect(subject.currentRecordingDevice() == builtIn)
    }

    @Test func refreshDevicesFallsBackToBuiltInButPreservesExternalPreference() {
        let defaults = TestSupport.makeUserDefaults()
        let builtIn = makeDevice(id: 1, uid: "built-in", name: "MacBook Microphone", transportType: kAudioDeviceTransportTypeBuiltIn)
        let usb = makeDevice(id: 2, uid: "usb", name: "USB Mic", transportType: kAudioDeviceTransportTypeUSB)
        let provider = TestAudioDeviceProvider(
            inputDevices: [builtIn, usb],
            defaultInputDevice: builtIn
        )

        let subject = AudioDeviceSelectionManager(provider: provider, defaults: defaults)
        subject.selectDevice(usb)

        #expect(defaults.string(forKey: MacPreferences.preferredAudioInputDeviceUID) == usb.uid)
        #expect(subject.preference == .external(uid: usb.uid))
        #expect(subject.activeDevice == usb)

        provider.inputDevices = [builtIn]
        provider.defaultInputDeviceValue = builtIn
        subject.refreshDevices()

        #expect(subject.preference == .external(uid: usb.uid))
        #expect(subject.activeDevice == builtIn)
        #expect(subject.selectedDevice == builtIn)
        #expect(subject.currentRecordingDevice() == builtIn)
        #expect(subject.isUsingFallbackBuiltIn)
        #expect(defaults.string(forKey: MacPreferences.preferredAudioInputDeviceUID) == usb.uid)
    }

    @Test func refreshDevicesRestoresExternalDeviceWhenItReturns() {
        let defaults = TestSupport.makeUserDefaults()
        let builtIn = makeDevice(id: 1, uid: "built-in", name: "MacBook Microphone", transportType: kAudioDeviceTransportTypeBuiltIn)
        let usb = makeDevice(id: 2, uid: "usb", name: "USB Mic", transportType: kAudioDeviceTransportTypeUSB)
        let provider = TestAudioDeviceProvider(
            inputDevices: [builtIn, usb],
            defaultInputDevice: builtIn
        )

        let subject = AudioDeviceSelectionManager(provider: provider, defaults: defaults)
        subject.selectDevice(usb)

        provider.inputDevices = [builtIn]
        subject.refreshDevices()
        #expect(subject.activeDevice == builtIn)

        provider.inputDevices = [builtIn, usb]
        subject.refreshDevices()

        #expect(subject.preference == .external(uid: usb.uid))
        #expect(subject.activeDevice == usb)
        #expect(subject.selectedDevice == usb)
        #expect(subject.currentRecordingDevice() == usb)
        #expect(!subject.isUsingFallbackBuiltIn)
    }

    @Test func selectingBuiltInDefaultDuringFallbackClearsStoredExternalPreference() {
        let defaults = TestSupport.makeUserDefaults()
        let builtIn = makeDevice(id: 1, uid: "built-in", name: "MacBook Microphone", transportType: kAudioDeviceTransportTypeBuiltIn)
        let usb = makeDevice(id: 2, uid: "usb", name: "USB Mic", transportType: kAudioDeviceTransportTypeUSB)
        let provider = TestAudioDeviceProvider(
            inputDevices: [builtIn, usb],
            defaultInputDevice: builtIn
        )

        let subject = AudioDeviceSelectionManager(provider: provider, defaults: defaults)
        subject.selectDevice(usb)

        provider.inputDevices = [builtIn]
        subject.refreshDevices()
        #expect(subject.activeDevice == builtIn)
        #expect(defaults.string(forKey: MacPreferences.preferredAudioInputDeviceUID) == usb.uid)

        subject.selectBuiltInDefault()
        #expect(subject.preference == .builtInDefault)
        #expect(subject.activeDevice == builtIn)
        #expect(defaults.string(forKey: MacPreferences.preferredAudioInputDeviceUID) == nil)

        provider.inputDevices = [builtIn, usb]
        subject.refreshDevices()

        #expect(subject.preference == .builtInDefault)
        #expect(subject.activeDevice == builtIn)
        #expect(subject.selectedDevice == builtIn)
    }
}

private final class TestAudioDeviceProvider: AudioDeviceProviding, @unchecked Sendable {
    var inputDevices: [AudioHardwareDevice]
    var defaultInputDeviceValue: AudioHardwareDevice?

    init(
        inputDevices: [AudioHardwareDevice],
        defaultInputDevice: AudioHardwareDevice?
    ) {
        self.inputDevices = inputDevices
        self.defaultInputDeviceValue = defaultInputDevice
    }

    func allInputDevices() -> [AudioHardwareDevice] {
        inputDevices
    }

    func defaultInputDevice() -> AudioHardwareDevice? {
        defaultInputDeviceValue
    }
}

private func makeDevice(
    id: AudioDeviceID,
    uid: String,
    name: String,
    transportType: UInt32
) -> AudioHardwareDevice {
    AudioHardwareDevice(
        id: id,
        uid: uid,
        name: name,
        transportType: transportType
    )
}
#endif
