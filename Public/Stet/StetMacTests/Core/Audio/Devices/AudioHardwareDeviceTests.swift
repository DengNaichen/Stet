#if os(macOS)
    import CoreAudio
    import Testing

    @testable import Stet

    @Suite("Audio Hardware Device")
    struct AudioHardwareDeviceTests {
        @Test func isBuiltInReturnsTrueForBuiltInTransportType() {
            let device = AudioHardwareDevice(
                id: 1,
                uid: "built-in",
                name: "MacBook Microphone",
                transportType: kAudioDeviceTransportTypeBuiltIn
            )

            #expect(device.isBuiltIn)
        }

        @Test func isBuiltInReturnsFalseForNonBuiltInTransportType() {
            let device = AudioHardwareDevice(
                id: 2,
                uid: "usb",
                name: "USB Mic",
                transportType: kAudioDeviceTransportTypeUSB
            )

            #expect(!device.isBuiltIn)
        }

        @Test func isHandheldAppleDeviceDetectsIPhone() {
            let device = AudioHardwareDevice(
                id: 3,
                uid: "iphone",
                name: "iPhone Microphone",
                transportType: kAudioDeviceTransportTypeBluetooth
            )

            #expect(device.isHandheldAppleDevice)
        }

        @Test func isHandheldAppleDeviceDetectsIPad() {
            let device = AudioHardwareDevice(
                id: 4,
                uid: "ipad",
                name: "iPad Pro",
                transportType: kAudioDeviceTransportTypeBluetooth
            )

            #expect(device.isHandheldAppleDevice)
        }

        @Test func automaticSelectionPriorityRanksBuiltInHighest() {
            let builtIn = AudioHardwareDevice(
                id: 1,
                uid: "built-in",
                name: "Built-in",
                transportType: kAudioDeviceTransportTypeBuiltIn
            )
            let usb = AudioHardwareDevice(
                id: 2,
                uid: "usb",
                name: "USB",
                transportType: kAudioDeviceTransportTypeUSB
            )

            #expect(builtIn.automaticSelectionPriority > usb.automaticSelectionPriority)
        }

        @Test func automaticSelectionPriorityRanksUSBOverBluetooth() {
            let usb = AudioHardwareDevice(
                id: 2,
                uid: "usb",
                name: "USB",
                transportType: kAudioDeviceTransportTypeUSB
            )
            let bluetooth = AudioHardwareDevice(
                id: 3,
                uid: "bt",
                name: "AirPods",
                transportType: kAudioDeviceTransportTypeBluetooth
            )

            #expect(usb.automaticSelectionPriority > bluetooth.automaticSelectionPriority)
        }

        @Test func automaticSelectionPriorityRanksHandheldAppleDeviceLowest() {
            let bluetooth = AudioHardwareDevice(
                id: 3,
                uid: "bt",
                name: "AirPods",
                transportType: kAudioDeviceTransportTypeBluetooth
            )
            let iphone = AudioHardwareDevice(
                id: 4,
                uid: "iphone",
                name: "iPhone",
                transportType: kAudioDeviceTransportTypeBluetooth
            )

            #expect(bluetooth.automaticSelectionPriority > iphone.automaticSelectionPriority)
        }

        @Test func devicesWithSamePropertiesAreEqual() {
            let device1 = AudioHardwareDevice(
                id: 1,
                uid: "test",
                name: "Test Device",
                transportType: kAudioDeviceTransportTypeUSB
            )
            let device2 = AudioHardwareDevice(
                id: 1,
                uid: "test",
                name: "Test Device",
                transportType: kAudioDeviceTransportTypeUSB
            )

            #expect(device1 == device2)
        }

        @Test func devicesWithDifferentUIDsAreNotEqual() {
            let device1 = AudioHardwareDevice(
                id: 1,
                uid: "test1",
                name: "Test Device",
                transportType: kAudioDeviceTransportTypeUSB
            )
            let device2 = AudioHardwareDevice(
                id: 1,
                uid: "test2",
                name: "Test Device",
                transportType: kAudioDeviceTransportTypeUSB
            )

            #expect(device1 != device2)
        }
    }
#endif
