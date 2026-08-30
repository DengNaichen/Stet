import Testing

@testable import StetCore

@Suite("Stored Transcription Engine")
struct StoredTranscriptionEngineTests {
    @Test func supportedCasesAndDefaultExcludeRetiredSenseVoice() {
        #expect(StoredTranscriptionEngine.allCases == [.fluidAudio, .funASRNano, .localWhisper])
        #expect(StoredTranscriptionEngine.default == .funASRNano)
        #expect(StoredTranscriptionEngine(rawValue: "sherpaOnnxSenseVoice") == nil)
    }
}
