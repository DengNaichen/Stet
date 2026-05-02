import AVFoundation
import Foundation
import Speech

@available(iOS 26.0, *)
final class AppleSpeechASREngine: ASREngine {
    let name = "Speech Analyzer (iOS 26)"

    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var analysisTask: Task<Void, Error>?
    private var resultsTask: Task<Void, Never>?

    private var audioEngine: AVAudioEngine?
    private var converter: AVAudioConverter?
    private var analyzerFormat: AVAudioFormat?

    private var activeSessionId: String?
    private var routeChangeObserver: NSObjectProtocol?

    let resultStream: AsyncStream<ASRResult>
    private let continuation: AsyncStream<ASRResult>.Continuation

    init() {
        let (stream, cont) = AsyncStream<ASRResult>.makeStream()
        self.resultStream = stream
        self.continuation = cont
    }

    func prepare() async throws {
        guard audioEngine == nil else { return }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.channelCount > 0 else {
            throw NSError(domain: "AppleSpeechASREngine", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Audio input unavailable"])
        }

        // Tap with the native format. The converter to analyzerFormat is created on start()
        // because the analyzer's preferred format depends on the transcriber.
        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.handleInputBuffer(buffer)
        }
        engine.prepare()
        try engine.start()
        self.audioEngine = engine
        registerRouteChangeObserver()
    }

    func start(sessionId: String) async throws {
        if audioEngine == nil { try await prepare() }
        cleanupSessionState()

        let transcriber = SpeechTranscriber(
            locale: Locale(identifier: "zh-CN"),
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
        self.transcriber = transcriber

        if let installationRequest = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await installationRequest.downloadAndInstall()
        }

        guard let audioEngine = audioEngine else {
            throw NSError(domain: "AppleSpeechASREngine", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "Audio engine missing"])
        }

        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw NSError(domain: "AppleSpeechASREngine", code: -3,
                          userInfo: [NSLocalizedDescriptionKey: "Could not determine analyzer audio format"])
        }
        self.analyzerFormat = analyzerFormat

        let inputFormat = audioEngine.inputNode.outputFormat(forBus: 0)
        guard let converter = AVAudioConverter(from: inputFormat, to: analyzerFormat) else {
            throw NSError(domain: "AppleSpeechASREngine", code: -4,
                          userInfo: [NSLocalizedDescriptionKey: "Could not create audio converter"])
        }
        self.converter = converter

        let (inputStream, inputContinuation) = AsyncStream<AnalyzerInput>.makeStream()
        self.inputContinuation = inputContinuation

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer

        analysisTask = Task {
            try await analyzer.start(inputSequence: inputStream)
        }

        resultsTask = Task { [weak self] in
            guard let self = self else { return }
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    let asrResult = ASRResult(text: text, isFinal: result.isFinal, metrics: nil)
                    self.continuation.yield(asrResult)
                }
            } catch {
                // Stream ended or task cancelled; ignore.
            }
        }

        // Audio engine should already be running from prepare(); ensure session is active
        // in case the system deactivated it (e.g. interruption recovery).
        if !audioEngine.isRunning {
            try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
            try audioEngine.start()
        }

        activeSessionId = sessionId
    }

    func stop() {
        guard activeSessionId != nil else { return }

        let pendingAnalyzer = analyzer
        inputContinuation?.finish()
        inputContinuation = nil

        Task {
            try? await pendingAnalyzer?.finalizeAndFinishThroughEndOfInput()
        }

        activeSessionId = nil
        // Keep audioEngine running across sessions for fast restart and stable AirPods routing.
    }

    func teardown() {
        unregisterRouteChangeObserver()
        cleanupSessionState()
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        activeSessionId = nil
        continuation.finish()
    }

    private func registerRouteChangeObserver() {
        guard routeChangeObserver == nil else { return }
        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            self?.handleRouteChange(note)
        }
    }

    private func unregisterRouteChangeObserver() {
        if let token = routeChangeObserver {
            NotificationCenter.default.removeObserver(token)
            routeChangeObserver = nil
        }
    }

    private func handleRouteChange(_ note: Notification) {
        guard let engine = audioEngine else { return }
        let input = engine.inputNode
        let newInputFormat = input.outputFormat(forBus: 0)
        guard newInputFormat.channelCount > 0 else { return }

        // Skip if format hasn't actually changed.
        if let existing = converter,
           existing.inputFormat.sampleRate == newInputFormat.sampleRate,
           existing.inputFormat.channelCount == newInputFormat.channelCount {
            return
        }

        let wasRunning = engine.isRunning
        engine.stop()
        input.removeTap(onBus: 0)

        // Rebuild converter to current analyzerFormat (if a session is active and analyzerFormat exists).
        if let analyzerFormat = self.analyzerFormat,
           let newConverter = AVAudioConverter(from: newInputFormat, to: analyzerFormat) {
            self.converter = newConverter
        } else {
            // No active session; converter will be rebuilt on next start(sessionId:).
            self.converter = nil
        }

        input.installTap(onBus: 0, bufferSize: 1024, format: newInputFormat) { [weak self] buffer, _ in
            self?.handleInputBuffer(buffer)
        }
  
        if wasRunning {
            do {
                try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
                try engine.start()
            } catch {
            }
        }
    }

    private func cleanupSessionState() {
        inputContinuation?.finish()
        inputContinuation = nil
        analysisTask?.cancel()
        analysisTask = nil
        resultsTask?.cancel()
        resultsTask = nil
        analyzer = nil
        transcriber = nil
        converter = nil
        analyzerFormat = nil
    }

    private func handleInputBuffer(_ buffer: AVAudioPCMBuffer) {
        guard activeSessionId != nil,
              let converter = self.converter,
              let targetFormat = self.analyzerFormat,
              let inputContinuation = self.inputContinuation else { return }

        var consumed = false
        let inputBlock: AVAudioConverterInputBlock = { _, status in
            if consumed { status.pointee = .noDataNow; return nil }
            consumed = true
            status.pointee = .haveData
            return buffer
        }

        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let frameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
        guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCapacity) else { return }

        var error: NSError?
        converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)
        if error == nil {
            inputContinuation.yield(AnalyzerInput(buffer: convertedBuffer))
        }
    }
}
