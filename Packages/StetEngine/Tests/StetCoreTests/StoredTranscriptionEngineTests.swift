import Testing

@testable import StetCore

@Suite("Stored Transcription Engine")
struct StoredTranscriptionEngineTests {
    @Test func supportedCasesExcludeRetiredEngines() {
        #expect(StoredTranscriptionEngine.allCases == [.funASRNano, .fluidAudio])
        #expect(StoredTranscriptionEngine.default == .funASRNano)
        #expect(StoredTranscriptionEngine(rawValue: "sherpaOnnxSenseVoice") == nil)
        #expect(StoredTranscriptionEngine(rawValue: "localWhisper") == nil)
    }
}
