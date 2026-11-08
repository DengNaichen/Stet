#if os(macOS)
    import CoreAudio
    import Testing

    @testable import Stet

    @MainActor
    @Suite("Audio Input Device Query Contracts")
    struct AudioInputDeviceQueryContractTests {
        @Test func enumerationKeepsHealthyDevicesWhenOtherPropertiesFail() {
            let healthy = QueryDevice(id: 1)
            let noInput = QueryDevice(id: 2, inputChannels: [0])
            let multipleBuffers = QueryDevice(id: 3, inputChannels: [0, 2])
            let brokenInput = QueryDevice(id: 4, failure: .input)
            let brokenName = QueryDevice(id: 5, failure: .name)
            let brokenUID = QueryDevice(id: 6, failure: .uid)
            let brokenTransport = QueryDevice(id: 7, failure: .transport)
            let emptyName = QueryDevice(id: 8, deviceName: "")
            let system = QuerySystem(devices: [
                healthy, noInput, multipleBuffers, brokenInput, brokenName, brokenUID, brokenTransport, emptyName,
            ])

            let result = AudioInputDeviceManager.allInputDevices(system: system)
            #expect(result.map(\.id) == [1, 3, 7])
            #expect(result.first?.uid == "uid-1")
            #expect(result.first?.name == "Microphone")
            #expect(result.first?.transportType == kAudioDeviceTransportTypeUSB)
            #expect(result.last?.transportType == kAudioDeviceTransportTypeUnknown)
        }

        @Test func failedEnumerationReturnsEmptyList() {
            let system = QuerySystem(devices: [QueryDevice(id: 1)], fails: true)
            #expect(AudioInputDeviceManager.allInputDevices(system: system).isEmpty)
        }

        @Test func defaultIDsDoNotDependOnReadableMetadataOrInputChannels() {
            let input = QueryDevice(id: 1)
            let output = QueryDevice(id: 2, inputChannels: [])
            let system = QuerySystem(input: input, output: output)
            #expect(AudioInputDeviceManager.defaultInputDeviceID(system: system) == 1)
            #expect(AudioInputDeviceManager.defaultInputDevice(system: system)?.id == 1)
            #expect(AudioInputDeviceManager.defaultOutputDeviceID(system: system) == 2)
            #expect(AudioInputDeviceManager.defaultOutputDevice(system: system)?.id == 2)

            let unreadable = QuerySystem(input: QueryDevice(id: 3, failure: .name))
            #expect(AudioInputDeviceManager.defaultInputDeviceID(system: unreadable) == 3)
            #expect(AudioInputDeviceManager.defaultInputDevice(system: unreadable) == nil)
        }

        @Test func missingUnknownAndFailedDefaultsReturnNil() {
            for system in [
                QuerySystem(), QuerySystem(input: QueryDevice(id: 0), output: QueryDevice(id: 0)),
                QuerySystem(fails: true),
            ] {
                #expect(AudioInputDeviceManager.defaultInputDeviceID(system: system) == nil)
                #expect(AudioInputDeviceManager.defaultOutputDeviceID(system: system) == nil)
                #expect(AudioInputDeviceManager.defaultInputDevice(system: system) == nil)
                #expect(AudioInputDeviceManager.defaultOutputDevice(system: system) == nil)
            }
        }
    }

    // Immutable fake SDK objects keep tests independent of the host's audio hardware.
    private nonisolated final class QuerySystem: AudioHardwareSystem, @unchecked Sendable {
        let values: [CoreAudio.AudioHardwareDevice]
        let input: CoreAudio.AudioHardwareDevice?
        let output: CoreAudio.AudioHardwareDevice?
        let fails: Bool

        init(
            devices: [CoreAudio.AudioHardwareDevice] = [], input: CoreAudio.AudioHardwareDevice? = nil,
            output: CoreAudio.AudioHardwareDevice? = nil, fails: Bool = false
        ) {
            self.values = devices
            self.input = input
            self.output = output
            self.fails = fails
            super.init(id: AudioObjectID(kAudioObjectSystemObject))
        }

        override var devices: [CoreAudio.AudioHardwareDevice] {
            get throws {
                if fails { throw AudioHardwareError(kAudioHardwareUnspecifiedError) }
                return values
            }
        }
        override var defaultInputDevice: CoreAudio.AudioHardwareDevice? {
            get throws {
                if fails { throw AudioHardwareError(kAudioHardwareUnspecifiedError) }
                return input
            }
        }
        override var defaultOutputDevice: CoreAudio.AudioHardwareDevice? {
            get throws {
                if fails { throw AudioHardwareError(kAudioHardwareUnspecifiedError) }
                return output
            }
        }
    }

    private nonisolated final class QueryDevice: CoreAudio.AudioHardwareDevice, @unchecked Sendable {
        enum Failure { case input, name, uid, transport }
        let inputChannels: [UInt32]
        let deviceName: String
        let failure: Failure?

        init(
            id: AudioObjectID, inputChannels: [UInt32] = [1], deviceName: String = "Microphone", failure: Failure? = nil
        ) {
            self.inputChannels = inputChannels
            self.deviceName = deviceName
            self.failure = failure
            super.init(id: id)
        }

        override var inputStreamConfiguration: [AudioBuffer] {
            get throws {
                if failure == .input { throw AudioHardwareError(kAudioHardwareBadObjectError) }
                return inputChannels.map { AudioBuffer(mNumberChannels: $0, mDataByteSize: 0, mData: nil) }
            }
        }
        override var name: String {
            get throws {
                if failure == .name { throw AudioHardwareError(kAudioHardwareBadObjectError) }
                return deviceName
            }
        }
        override var uid: String {
            get throws {
                if failure == .uid { throw AudioHardwareError(kAudioHardwareBadObjectError) }
                return "uid-\(id)"
            }
        }
        override var transportType: UInt32 {
            get throws {
                if failure == .transport { throw AudioHardwareError(kAudioHardwareBadObjectError) }
                return kAudioDeviceTransportTypeUSB
            }
        }
    }
#endif
