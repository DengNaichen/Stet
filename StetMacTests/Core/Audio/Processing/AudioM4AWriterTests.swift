import AVFoundation
import Testing

@testable import Stet

@MainActor
@Suite("Audio M4A Writer")
struct AudioM4AWriterTests {
    @Test func encodingCanFinishWhileMainActorIsOccupied() async throws {
        let samples = (0..<16_000).map { Float(sin(Double($0) * 0.1) * 0.1) }
        let finished = DispatchSemaphore(value: 0)
        let encoding = Task.detached {
            defer { finished.signal() }
            return try AudioM4AWriter.writeAACM4A(
                samples: samples, sampleRate: 16_000, filePrefix: "isolation-test")
        }
        let completedWithoutMainActor = waitForBackgroundWork(finished)
        let url = try await encoding.value
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(completedWithoutMainActor)
        let file = try AVAudioFile(forReading: url)
        #expect(file.length > 0)
        #expect(file.fileFormat.sampleRate == 16_000)
        #expect(file.fileFormat.channelCount == 1)
    }

    // Occupy MainActor synchronously to catch an accidental hop from the background writer.
    private func waitForBackgroundWork(_ finished: DispatchSemaphore) -> Bool {
        finished.wait(timeout: .now() + 2) == .success
    }
}
