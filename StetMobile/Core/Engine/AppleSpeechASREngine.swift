import AVFoundation
import Foundation
import Speech

@available(iOS 26.0, *)
class AppleSpeechASREngine: ASREngine {
    let name = "Speech Analyzer (iOS 26)"
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var analysisTask: Task<Void, Error>?
    private var resultsTask: Task<Void, Never>?
    
    private var audioEngine: AVAudioEngine?
    private var converter: AVAudioConverter?
    private var analyzerFormat: AVAudioFormat?
    private var continuation: AsyncStream<ASRResult>.Continuation?
    
    // Use a single stream instance to avoid overwriting continuation
    private(set) lazy var resultStream: AsyncStream<ASRResult> = {
        AsyncStream { continuation in
            self.continuation = continuation
        }
    }()
    
    init() {}
    
    func start(sessionId: String) async throws {
        // Ensure everything is stopped before starting
        stop()
        
        // 1. Setup the transcriber module with volatile results for real-time feedback
        let transcriber = SpeechTranscriber(
            locale: .current,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
        self.transcriber = transcriber
        
        // 2. Model Asset Management
        // Ensure required assets are downloaded/installed
        if let installationRequest = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            // Note: In a real app, you might want to handle progress or errors here
            try await installationRequest.downloadAndInstall()
        }
        
        // 3. Setup the input stream using AnalyzerInput
        let (inputStream, inputContinuation) = AsyncStream<AnalyzerInput>.makeStream()
        self.inputContinuation = inputContinuation
        
        // 4. Initialize the analyzer with the module
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer
        
        // 5. Start the analysis process
        analysisTask = Task {
            try await analyzer.start(inputSequence: inputStream)
        }
        
        // 6. Handle results from the transcriber
        resultsTask = Task {
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    let asrResult = ASRResult(
                        text: text,
                        isFinal: result.isFinal,
                        metrics: nil
                    )
                    self.continuation?.yield(asrResult)
                }
            } catch {
                // Yield an error if possible, or just finish
            }
        }
        
        // 7. Start audio capture with format validation
        try await setupAudioEngine()
    }
    
    private func setupAudioEngine() async throws {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        
        // Get the best available format for the analyzer (e.g., 16kHz, Int16)
        guard let transcriber = transcriber else { return }
        guard let targetFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw NSError(domain: "AppleSpeechASREngine", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not determine best available audio format"])
        }
        self.analyzerFormat = targetFormat
        
        // Setup converter from native input format to analyzer's preferred format
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw NSError(domain: "AppleSpeechASREngine", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not create audio converter"])
        }
        self.converter = converter
        
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        
        // Tap using the NATIVE format to avoid crash
        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.handleInputBuffer(buffer)
        }
        
        try engine.start()
        self.audioEngine = engine
    }
    
    private func handleInputBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let converter = self.converter, let targetFormat = self.analyzerFormat else { return }
        
        // Perform resampling/format conversion
        var consumed = false
        let inputBlock: AVAudioConverterInputBlock = { _, status in
            if consumed { status.pointee = .noDataNow; return nil }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        
        // Calculate required capacity for the converted buffer
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let frameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
        
        guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCapacity) else { return }
        
        var error: NSError?
        converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)
        
        if error == nil {
            let analyzerInput = AnalyzerInput(buffer: convertedBuffer)
            self.inputContinuation?.yield(analyzerInput)
        }
    }
    
    func stop() {
        // 1. Finish input stream
        inputContinuation?.finish()
        inputContinuation = nil
        
        // 2. Stop audio engine and remove tap
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        
        // 3. Cancel tasks and finalize analyzer
        let currentAnalyzer = analyzer
        let currentAnalysisTask = analysisTask
        let currentResultsTask = resultsTask
        
        Task {
            if let analyzer = currentAnalyzer {
                // Essential to call this to process remaining volatile results
                try? await analyzer.finalizeAndFinishThroughEndOfInput()
            }
            currentAnalysisTask?.cancel()
            currentResultsTask?.cancel()
        }
        
        analyzer = nil
        transcriber = nil
        analysisTask = nil
        resultsTask = nil
    }
}
