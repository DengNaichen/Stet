#if os(macOS)
import AVFoundation
import Testing

@testable import Stet

@Suite("Mac Recording File Stabilizer")
struct MacRecordingFileStabilizerTests {
    @Test func waitForFileToStabilizeWaitsForFileToExist() async throws {
        let fileURL = TestSupport.temporaryFileURL(ext: "wav")
        try? FileManager.default.removeItem(at: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        
        let writerTask = Task {
            try? await Task.sleep(for: .milliseconds(100))
            let outputFormat = try #require(TranscriptionUploadAudioFormat.makeMacOutputFormat())
            let audioFile = try AVAudioFile(
                forWriting: fileURL,
                settings: outputFormat.settings,
                commonFormat: outputFormat.commonFormat,
                interleaved: outputFormat.isInterleaved
            )
            let buffer = try #require(makeOutputBuffer(format: outputFormat))
            try audioFile.write(from: buffer)
        }
        
        await MacRecordingFileStabilizer.waitForFileToStabilize(at: fileURL)
        _ = await writerTask.result
        
        let reopenedFile = try AVAudioFile(forReading: fileURL)
        #expect(reopenedFile.length > 0)
    }
    
    @Test func waitForFileToStabilizeHandlesExistingFile() async throws {
        let fileURL = TestSupport.temporaryFileURL(ext: "wav")
        try? FileManager.default.removeItem(at: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        
        let outputFormat = try #require(TranscriptionUploadAudioFormat.makeMacOutputFormat())
        let audioFile = try AVAudioFile(
            forWriting: fileURL,
            settings: outputFormat.settings,
            commonFormat: outputFormat.commonFormat,
            interleaved: outputFormat.isInterleaved
        )
        let buffer = try #require(makeOutputBuffer(format: outputFormat))
        try audioFile.write(from: buffer)
        
        await MacRecordingFileStabilizer.waitForFileToStabilize(at: fileURL)
        
        let reopenedFile = try AVAudioFile(forReading: fileURL)
        #expect(reopenedFile.length > 0)
    }
    
    private func makeOutputBuffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let frameCount: AVAudioFrameCount = 1_600
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channelData = buffer.int16ChannelData else {
            return nil
        }
        
        buffer.frameLength = frameCount
        
        for index in 0..<Int(frameCount) {
            channelData[0][index] = Int16((index % 200) - 100)
        }
        
        return buffer
    }
}
#endif
