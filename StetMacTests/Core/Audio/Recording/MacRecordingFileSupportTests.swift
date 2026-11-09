#if os(macOS)
    import AVFoundation
    import Testing

    @testable import Stet

    @MainActor
    @Suite("Mac Recording File Support")
    struct MacRecordingFileSupportTests {
        @Test func recordingSessionBuffersAudioBeforeActivationAndWritesItOnceActivated() async throws {
            let outputFormat = try #require(TranscriptionUploadAudioFormat.makeMacOutputFormat())
            let inputFormat = try #require(
                AVAudioFormat(
                    commonFormat: .pcmFormatFloat32,
                    sampleRate: 48_000,
                    channels: 2,
                    interleaved: false
                )
            )
            let fileURL = TestSupport.temporaryFileURL(ext: "wav")
            try? FileManager.default.removeItem(at: fileURL)
            defer { try? FileManager.default.removeItem(at: fileURL) }

            var recordingFile: AVAudioFile? = try AVAudioFile(
                forWriting: fileURL,
                settings: outputFormat.settings,
                commonFormat: outputFormat.commonFormat,
                interleaved: outputFormat.isInterleaved
            )
            let session = MacAudioFileRecordingSession(
                recordingFile: try #require(recordingFile),
                outputFormat: outputFormat,
                voiceProcessingEnabled: true,
                voiceProcessingFallbackReason: nil
            )
            let inputBuffer = try #require(Self.makeInputBuffer(format: inputFormat))
            let normalization = MacNormalizedAudioCaptureSession(outputFormat: outputFormat)
            let convertedBuffer = try normalization.convert(inputBuffer).buffer

            let beforeActivation = try #require(try session.ingestConvertedBuffer(convertedBuffer))
            #expect(!beforeActivation.didWriteAudioFrames)
            #expect(session.recordingOutcome().writtenFrameCount == 0)

            try session.activateRecordingWindow()
            try session.activateRecordingWindow()
            let afterActivation = try #require(try session.ingestConvertedBuffer(convertedBuffer))
            #expect(afterActivation.didWriteAudioFrames)

            let outcome = session.recordingOutcome()
            session.close()
            recordingFile = nil
            #expect(try session.ingestConvertedBuffer(convertedBuffer) == nil)

            #expect(outcome.writtenFrameCount == AVAudioFramePosition(convertedBuffer.frameLength * 2))
            #expect(outcome.didWriteAudio)
        }

        @Test func recordingOutcomeIncludesVoiceProcessingFallbackDetails() throws {
            let outputFormat = try #require(TranscriptionUploadAudioFormat.makeMacOutputFormat())
            let fileURL = TestSupport.temporaryFileURL(ext: "wav")
            try? FileManager.default.removeItem(at: fileURL)
            defer { try? FileManager.default.removeItem(at: fileURL) }

            let recordingFile = try AVAudioFile(
                forWriting: fileURL,
                settings: outputFormat.settings,
                commonFormat: outputFormat.commonFormat,
                interleaved: outputFormat.isInterleaved
            )
            let session = MacAudioFileRecordingSession(
                recordingFile: recordingFile,
                outputFormat: outputFormat,
                voiceProcessingEnabled: false,
                voiceProcessingFallbackReason: "unsupported route"
            )

            let outcome = session.recordingOutcome()
            session.close()

            #expect(!outcome.didWriteAudio)
            #expect(outcome.captureDiagnosticsSummary?.contains("voiceProcessingEnabled=false") == true)
            #expect(outcome.captureDiagnosticsSummary?.contains("fallbackReason=unsupported route") == true)
        }

        @Test(arguments: [
            [10_000, 10_000, 10_000],
            [10_000, 10_000, 10_000, 10_000, 10_000],
            [30_000],
            [12_000, 12_000],
            [1_600],
        ])
        func preActivationBufferRetainsExactBoundedSuffix(frameCounts: [Int]) throws {
            let outputFormat = try #require(TranscriptionUploadAudioFormat.makeMacOutputFormat())
            let fileURL = TestSupport.temporaryFileURL(ext: "wav")
            try? FileManager.default.removeItem(at: fileURL)
            defer { try? FileManager.default.removeItem(at: fileURL) }

            var recordingFile: AVAudioFile? = try AVAudioFile(
                forWriting: fileURL,
                settings: outputFormat.settings,
                commonFormat: outputFormat.commonFormat,
                interleaved: outputFormat.isInterleaved
            )
            let session = MacAudioFileRecordingSession(
                recordingFile: try #require(recordingFile),
                outputFormat: outputFormat,
                voiceProcessingEnabled: false,
                voiceProcessingFallbackReason: nil
            )

            var capturedSamples: [Int16] = []
            for (index, frameCount) in frameCounts.enumerated() {
                let value = Int16(index + 1)
                capturedSamples += Array(repeating: value, count: frameCount)
                let buffer = try #require(
                    Self.makeOutputBuffer(format: outputFormat, frameCount: AVAudioFrameCount(frameCount), value: value)
                )
                _ = try session.ingestConvertedBuffer(buffer)
            }
            try session.activateRecordingWindow()
            let outcome = session.recordingOutcome()
            session.close()
            recordingFile = nil

            let expectedSamples = Array(capturedSamples.suffix(24_000))
            #expect(outcome.writtenFrameCount == AVAudioFramePosition(expectedSamples.count))
            let file = try AVAudioFile(forReading: fileURL, commonFormat: .pcmFormatInt16, interleaved: false)
            #expect(file.length == AVAudioFramePosition(expectedSamples.count))
            let readBuffer = try #require(
                AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
            try file.read(into: readBuffer)
            let samples = try #require(readBuffer.int16ChannelData?[0])
            #expect(Array(UnsafeBufferPointer(start: samples, count: Int(readBuffer.frameLength))) == expectedSamples)
        }

        @Test func recordingFileStabilizerWaitsUntilFileBecomesReadable() async throws {
            let outputFormat = try #require(TranscriptionUploadAudioFormat.makeMacOutputFormat())
            let fileURL = TestSupport.temporaryFileURL(ext: "wav")
            try? FileManager.default.removeItem(at: fileURL)
            defer { try? FileManager.default.removeItem(at: fileURL) }

            let writerTask = Task {
                try? await Task.sleep(for: .milliseconds(120))
                let audioFile = try AVAudioFile(
                    forWriting: fileURL,
                    settings: outputFormat.settings,
                    commonFormat: outputFormat.commonFormat,
                    interleaved: outputFormat.isInterleaved
                )
                let buffer = try #require(Self.makeOutputBuffer(format: outputFormat))
                try audioFile.write(from: buffer)
            }

            await MacRecordingFileStabilizer.waitForFileToStabilize(at: fileURL)
            _ = await writerTask.result

            let reopenedFile = try AVAudioFile(forReading: fileURL)
            #expect(reopenedFile.length == 1_600)
        }

        private static func makeInputBuffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
            let frameCount: AVAudioFrameCount = 4_096
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
                let channelData = buffer.floatChannelData
            else {
                return nil
            }

            buffer.frameLength = frameCount

            for channel in 0..<Int(format.channelCount) {
                for index in 0..<Int(frameCount) {
                    channelData[channel][index] = Float((index % 200) - 100) / 100
                }
            }

            return buffer
        }

        private static func makeOutputBuffer(
            format: AVAudioFormat,
            frameCount: AVAudioFrameCount = 1_600,
            value: Int16? = nil
        ) -> AVAudioPCMBuffer? {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
                let channelData = buffer.int16ChannelData
            else {
                return nil
            }

            buffer.frameLength = frameCount

            for index in 0..<Int(frameCount) {
                channelData[0][index] = value ?? Int16((index % 200) - 100)
            }

            return buffer
        }
    }
#endif
