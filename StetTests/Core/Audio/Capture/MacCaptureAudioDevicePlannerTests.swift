#if os(macOS)
    import AVFoundation
    import CoreAudio
    import Testing

    @testable import Stet

    @Suite("Mac Capture Audio Device Planner")
    struct MacCaptureAudioDevicePlannerTests {
        @Test func inputDeviceCandidatesWithSelectedDeviceIncludesSelectedFirst() {
            let selectedDevice = makeDevice(
                id: 2,
                uid: "test-selected-device-uid",
                name: "USB Mic",
                transportType: kAudioDeviceTransportTypeUSB
            )

            let candidates = MacCaptureAudioDevicePlanner.inputDeviceCandidates(selectedDevice: selectedDevice)

            #expect(candidates.count == 1)
            #expect(candidates[0].device?.uid == "test-selected-device-uid")
            #expect(candidates[0].reason == .selected)
        }

        @Test func inputDeviceCandidatesWithoutSelectedDeviceIncludesFallbacks() {
            let candidates = MacCaptureAudioDevicePlanner.inputDeviceCandidates(selectedDevice: nil)

            #expect(candidates.count >= 1)
            #expect(candidates[0].device == nil)
            #expect(candidates[0].reason == .noExplicitDeviceFallback)

            let nilCandidateCount = candidates.filter { $0.device == nil }.count
            #expect(nilCandidateCount == 1)

            let candidateUIDs = candidates.compactMap(\.device?.uid)
            #expect(Set(candidateUIDs).count == candidateUIDs.count)

            let trailingReasons = Array(candidates.dropFirst().map(\.reason))
            let allowedTrailingShapes: Set<[InputDeviceCandidate.Reason]> = [
                [],
                [.builtInFallback],
                [.systemDefaultFallback],
                [.builtInFallback, .systemDefaultFallback],
            ]
            #expect(allowedTrailingShapes.contains(trailingReasons))
        }

        @Test func availableCaptureDevicesReturnsNonEmptyList() {
            let devices = MacCaptureAudioDevicePlanner.availableCaptureDevices()

            for device in devices {
                #expect(!device.uniqueID.isEmpty)
                #expect(!device.localizedName.isEmpty)
            }
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
