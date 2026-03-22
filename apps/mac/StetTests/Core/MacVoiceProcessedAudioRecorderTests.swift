#if os(macOS)
import AVFoundation
import Testing

@testable import Stet

@MainActor
@Suite("Mac Voice Processed Audio Recorder")
struct MacVoiceProcessedAudioRecorderTests {
    @Test func prefersNativeVoiceProcessingPipeline() async throws {
        let nativeRecorder = MockMacRecordingFileRecorder(
            waitForCapturedAudioResult: true,
            stopOutcome: MacAudioFileRecordingOutcome(
                writtenFrameCount: 32,
                didWriteAudio: true,
                captureBackend: "AVAudioEngine",
                captureDiagnosticsSummary: "captureBackend=AVAudioEngine"
            )
        )
        let fallbackRecorder = MockMacRecordingFileRecorder()
        let recorder = MacVoiceProcessedAudioRecorder(
            nativeRecorder: nativeRecorder,
            fallbackRecorder: fallbackRecorder
        )
        let fileURL = TestSupport.temporaryFileURL(ext: "wav")
        let outputFormat = try #require(TranscriptionUploadAudioFormat.makeMacOutputFormat())

        try await recorder.startRecording(to: fileURL, outputFormat: outputFormat)
        try recorder.activateRecordingWindow()
        let outcome = await recorder.stopRecording(writtenFileAt: fileURL)

        #expect(nativeRecorder.startCallCount == 1)
        #expect(nativeRecorder.activateCallCount == 1)
        #expect(nativeRecorder.stopCallCount == 1)
        #expect(fallbackRecorder.startCallCount == 0)
        #expect(fallbackRecorder.activateCallCount == 0)
        #expect(fallbackRecorder.stopCallCount == 0)
        #expect(outcome.captureBackend == "AVAudioEngine")
    }

    @Test func fallsBackToAVCaptureWhenNativePipelineFails() async throws {
        let nativeRecorder = MockMacRecordingFileRecorder(startError: SpeechServiceError.failedToStart)
        let fallbackRecorder = MockMacRecordingFileRecorder(
            waitForCapturedAudioResult: true,
            stopOutcome: MacAudioFileRecordingOutcome(
                writtenFrameCount: 64,
                didWriteAudio: true,
                captureBackend: "AVCaptureSession",
                captureDiagnosticsSummary: "captureBackend=AVCaptureSession"
            )
        )
        let recorder = MacVoiceProcessedAudioRecorder(
            nativeRecorder: nativeRecorder,
            fallbackRecorder: fallbackRecorder
        )
        let fileURL = TestSupport.temporaryFileURL(ext: "wav")
        let outputFormat = try #require(TranscriptionUploadAudioFormat.makeMacOutputFormat())

        try await recorder.startRecording(to: fileURL, outputFormat: outputFormat)
        try recorder.activateRecordingWindow()
        let outcome = await recorder.stopRecording(writtenFileAt: fileURL)

        #expect(nativeRecorder.startCallCount == 1)
        #expect(nativeRecorder.activateCallCount == 0)
        #expect(nativeRecorder.stopCallCount == 0)
        #expect(fallbackRecorder.startCallCount == 1)
        #expect(fallbackRecorder.activateCallCount == 1)
        #expect(fallbackRecorder.stopCallCount == 1)
        #expect(outcome.captureBackend == "AVCaptureSession")
    }

    @Test func fallsBackToAVCaptureWhenNativePipelineProducesNoAudioBeforeDeadline() async throws {
        let nativeRecorder = MockMacRecordingFileRecorder(waitForCapturedAudioResult: false)
        let fallbackRecorder = MockMacRecordingFileRecorder(
            waitForCapturedAudioResult: true,
            stopOutcome: MacAudioFileRecordingOutcome(
                writtenFrameCount: 64,
                didWriteAudio: true,
                captureBackend: "AVCaptureSession",
                captureDiagnosticsSummary: "captureBackend=AVCaptureSession"
            )
        )
        let recorder = MacVoiceProcessedAudioRecorder(
            nativeRecorder: nativeRecorder,
            fallbackRecorder: fallbackRecorder
        )
        let fileURL = TestSupport.temporaryFileURL(ext: "wav")
        let outputFormat = try #require(TranscriptionUploadAudioFormat.makeMacOutputFormat())

        try await recorder.startRecording(to: fileURL, outputFormat: outputFormat)
        try recorder.activateRecordingWindow()
        let outcome = await recorder.stopRecording(writtenFileAt: fileURL)

        #expect(nativeRecorder.startCallCount == 1)
        #expect(nativeRecorder.waitCallCount == 1)
        #expect(nativeRecorder.cancelCallCount == 1)
        #expect(fallbackRecorder.startCallCount == 1)
        #expect(fallbackRecorder.waitCallCount == 1)
        #expect(fallbackRecorder.stopCallCount == 1)
        #expect(outcome.captureBackend == "AVCaptureSession")
    }
}

private final class MockMacRecordingFileRecorder: MacRecordingBackendRecorder, @unchecked Sendable {
    private let startError: Error?
    private let waitForCapturedAudioResult: Bool
    private let stopOutcome: MacAudioFileRecordingOutcome

    private(set) var startCallCount = 0
    private(set) var waitCallCount = 0
    private(set) var activateCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var cancelCallCount = 0
    private(set) var prewarmCallCount = 0

    init(
        startError: Error? = nil,
        waitForCapturedAudioResult: Bool = true,
        stopOutcome: MacAudioFileRecordingOutcome = .empty
    ) {
        self.startError = startError
        self.waitForCapturedAudioResult = waitForCapturedAudioResult
        self.stopOutcome = stopOutcome
    }

    func startRecordingAttempt(
        to fileURL: URL,
        outputFormat: AVAudioFormat,
        attempt: MacCaptureAttemptPlan
    ) throws {
        _ = fileURL
        _ = outputFormat
        _ = attempt
        startCallCount += 1
        if let startError {
            throw startError
        }
    }

    func waitForCapturedAudio(timeout: Duration) async -> Bool {
        _ = timeout
        waitCallCount += 1
        return waitForCapturedAudioResult
    }

    func activateRecordingWindow() throws {
        activateCallCount += 1
    }

    func stopRecording(writtenFileAt fileURL: URL) async -> MacAudioFileRecordingOutcome {
        _ = fileURL
        stopCallCount += 1
        return stopOutcome
    }

    func cancelRecording() {
        cancelCallCount += 1
    }

    func prewarm() {
        prewarmCallCount += 1
    }
}
#endif
