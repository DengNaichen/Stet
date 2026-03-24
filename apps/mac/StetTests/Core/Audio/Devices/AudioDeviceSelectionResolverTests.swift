#if os(macOS)
    import CoreAudio
    import Testing

    @testable import Stet

    @Suite("Audio Device Selection Resolver")
    struct AudioDeviceSelectionResolverTests {
        @Test func builtInDefaultPrefersBuiltInWhenPresent() {
            let builtIn = makeDevice(
                id: 1, uid: "built-in", name: "MacBook Microphone", transportType: kAudioDeviceTransportTypeBuiltIn)
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
            let bluetooth = makeDevice(
                id: 3, uid: "bt", name: "AirPods", transportType: kAudioDeviceTransportTypeBluetooth)

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
            let builtIn = makeDevice(
                id: 1, uid: "built-in", name: "MacBook Microphone", transportType: kAudioDeviceTransportTypeBuiltIn)
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
            let builtIn = makeDevice(
                id: 1, uid: "built-in", name: "MacBook Microphone", transportType: kAudioDeviceTransportTypeBuiltIn)
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

        @Test func resolveWithPreferenceEnumUsesBuiltInDefault() {
            let builtIn = makeDevice(
                id: 1, uid: "built-in", name: "MacBook Microphone", transportType: kAudioDeviceTransportTypeBuiltIn)
            let usb = makeDevice(id: 2, uid: "usb", name: "USB Mic", transportType: kAudioDeviceTransportTypeUSB)

            let resolution = AudioDeviceSelectionResolver.resolve(
                availableDevices: [builtIn, usb],
                defaultInputDevice: usb,
                preference: .builtInDefault
            )

            #expect(resolution.preference == .builtInDefault)
            #expect(resolution.activeDevice == builtIn)
        }

        @Test func resolveWithPreferenceEnumUsesExternalDevice() {
            let builtIn = makeDevice(
                id: 1, uid: "built-in", name: "MacBook Microphone", transportType: kAudioDeviceTransportTypeBuiltIn)
            let usb = makeDevice(id: 2, uid: "usb", name: "USB Mic", transportType: kAudioDeviceTransportTypeUSB)

            let resolution = AudioDeviceSelectionResolver.resolve(
                availableDevices: [builtIn, usb],
                defaultInputDevice: builtIn,
                preference: .external(uid: "usb")
            )

            #expect(resolution.preference == .external(uid: "usb"))
            #expect(resolution.activeDevice == usb)
        }
    }

    private func makeDevice(
        id: AudioDeviceID,
        uid: String,
        name: String,
        transportType: UInt32
    ) -> Stet.AudioHardwareDevice {
        Stet.AudioHardwareDevice(
            id: id,
            uid: uid,
            name: name,
            transportType: transportType
        )
    }
#endif
