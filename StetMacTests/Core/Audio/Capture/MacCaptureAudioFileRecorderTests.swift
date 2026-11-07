#if os(macOS)
    import AVFoundation
    import CoreAudio
    import Testing

    @testable import Stet

    @MainActor
    @Suite("Mac Capture Audio File Recorder", .serialized)
    struct MacCaptureAudioFileRecorderTests {
        @Test func stopRecordingWithoutStartingReturnsEmptyOutcome() async {
            let recorder = MacCaptureAudioFileRecorder()
            let fileURL = TestSupport.temporaryFileURL(ext: "wav")

            let outcome = await recorder.stopRecording(writtenFileAt: fileURL)

            #expect(outcome.writtenFrameCount == 0)
            #expect(!outcome.didWriteAudio)
            #expect(outcome.captureDiagnosticsSummary == nil)
        }

        @Test func activateRecordingWindowWithoutStartingDoesNotThrow() throws {
            let recorder = MacCaptureAudioFileRecorder()

            try recorder.activateRecordingWindow()
        }

        @Test func cancelRecordingWithoutStartingLeavesRecorderEmpty() async {
            let recorder = MacCaptureAudioFileRecorder()
            let fileURL = TestSupport.temporaryFileURL(ext: "wav")

            recorder.cancelRecording()
            let outcome = await recorder.stopRecording(writtenFileAt: fileURL)

            #expect(outcome.writtenFrameCount == 0)
            #expect(!outcome.didWriteAudio)
            #expect(outcome.captureDiagnosticsSummary == nil)
        }

        @Test func startRecordingWithUnavailableSelectedDeviceThrowsFailedToStartWithoutCreatingFile() throws {
            let recorder = MacCaptureAudioFileRecorder()
            let outputFormat = try #require(TranscriptionUploadAudioFormat.makeMacOutputFormat())
            let fileURL = TestSupport.temporaryFileURL(ext: "wav")
            try? FileManager.default.removeItem(at: fileURL)
            defer { try? FileManager.default.removeItem(at: fileURL) }

            #expect(throws: SpeechServiceError.failedToStart) {
                try recorder.startRecording(
                    to: fileURL,
                    outputFormat: outputFormat,
                    selectedDevice: Self.unavailableDevice()
                )
            }

            #expect(!FileManager.default.fileExists(atPath: fileURL.path))
        }

        @Test func failedStartLeavesRecorderReusableForAnotherAttempt() throws {
            let recorder = MacCaptureAudioFileRecorder()
            let outputFormat = try #require(TranscriptionUploadAudioFormat.makeMacOutputFormat())
            let firstURL = TestSupport.temporaryFileURL("failed-start-1", ext: "wav")
            let secondURL = TestSupport.temporaryFileURL("failed-start-2", ext: "wav")
            try? FileManager.default.removeItem(at: firstURL)
            try? FileManager.default.removeItem(at: secondURL)
            defer {
                try? FileManager.default.removeItem(at: firstURL)
                try? FileManager.default.removeItem(at: secondURL)
            }

            #expect(throws: SpeechServiceError.failedToStart) {
                try recorder.startRecording(
                    to: firstURL,
                    outputFormat: outputFormat,
                    selectedDevice: Self.unavailableDevice()
                )
            }

            #expect(throws: SpeechServiceError.failedToStart) {
                try recorder.startRecording(
                    to: secondURL,
                    outputFormat: outputFormat,
                    selectedDevice: Self.unavailableDevice()
                )
            }

            #expect(!FileManager.default.fileExists(atPath: firstURL.path))
            #expect(!FileManager.default.fileExists(atPath: secondURL.path))
        }

        private static func unavailableDevice() -> Stet.AudioHardwareDevice {
            Stet.AudioHardwareDevice(
                id: 999,
                uid: "stet-tests-unavailable-device-uid",
                name: "Stet Tests Unavailable Device",
                transportType: kAudioDeviceTransportTypeUSB
            )
        }
    }
#endif
