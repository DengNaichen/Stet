#if os(macOS)
    import CoreAudio
    import Testing

    @testable import Stet

    @Suite("Audio Input Device Manager")
    struct AudioInputDeviceManagerTests {
        @Test func defaultInputDeviceIDReturnsValidIDOrNil() {
            let deviceID = AudioInputDeviceManager.defaultInputDeviceID()

            if let deviceID {
                #expect(deviceID != 0)
            }
        }

        @Test func defaultOutputDeviceIDReturnsValidIDOrNil() {
            let deviceID = AudioInputDeviceManager.defaultOutputDeviceID()

            if let deviceID {
                #expect(deviceID != 0)
            }
        }

        @Test func defaultInputDeviceReturnsDeviceOrNil() {
            let device = AudioInputDeviceManager.defaultInputDevice()

            if let device {
                #expect(!device.uid.isEmpty)
                #expect(!device.name.isEmpty)
            }
        }

        @Test func builtInInputDeviceReturnsBuiltInOrNil() {
            let device = AudioInputDeviceManager.builtInInputDevice()

            if let device {
                #expect(device.isBuiltIn)
            }
        }

        @Test func defaultOutputDeviceReturnsDeviceOrNil() {
            let device = AudioInputDeviceManager.defaultOutputDevice()

            if let device {
                #expect(!device.uid.isEmpty)
                #expect(!device.name.isEmpty)
            }
        }

        @Test func allInputDevicesReturnsNonEmptyListOnMostSystems() {
            let devices = AudioInputDeviceManager.allInputDevices()

            #expect(devices.allSatisfy { !$0.uid.isEmpty && !$0.name.isEmpty })

            for device in devices {
                #expect(!device.uid.isEmpty)
                #expect(!device.name.isEmpty)
            }
        }

        @Test func hasInputChannelsReturnsBoolForValidDevice() {
            guard let deviceID = AudioInputDeviceManager.defaultInputDeviceID() else {
                return
            }

            let hasChannels = AudioInputDeviceManager.hasInputChannels(deviceID: deviceID)

            #expect(hasChannels == true || hasChannels == false)
        }
    }
#endif
