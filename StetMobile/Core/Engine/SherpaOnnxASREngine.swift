import AVFoundation
import Foundation
import StetAI
import CoreFoundation

final class SherpaOnnxASREngine: ASREngine {
    let name = "Sherpa-Onnx (SenseVoice)"

    private var recognizer: SherpaOnnxOfflineRecognizer?
    private var vad: SherpaOnnxVoiceActivityDetectorWrapper?
    private var audioEngine: AVAudioEngine?
    private var converter: AVAudioConverter?
    private let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)
    private let decodeQueue = DispatchQueue(label: "com.stetmobile.SherpaOnnxASREngine.decode")

    private var activeSessionId: String?
    private var routeChangeObserver: NSObjectProtocol?
    private var nextSegmentOrder: Int = 0
    private var decodedSegments: [Int: String] = [:]
    private var expectedSegmentCount: Int?
    private var sessionAudioSeconds: Double = 0
    private var sessionDecodeCpuSeconds: Double = 0
    private var sessionWallStart: CFAbsoluteTime = 0

    let resultStream: AsyncStream<ASRResult>
    private let continuation: AsyncStream<ASRResult>.Continuation

    init() {
        let (stream, cont) = AsyncStream<ASRResult>.makeStream()
        self.resultStream = stream
        self.continuation = cont
    }

    func prepare() async throws {
        try loadModelsIfNeeded()
        try configureAudioSessionAndEngine()
        registerRouteChangeObserver()
    }

    func start(sessionId: String) async throws {
        if audioEngine == nil { try await prepare() }

        activeSessionId = sessionId
        nextSegmentOrder = 0
        decodedSegments.removeAll()
        expectedSegmentCount = nil
        sessionAudioSeconds = 0
        sessionDecodeCpuSeconds = 0
        sessionWallStart = CFAbsoluteTimeGetCurrent()

        if let vad = vad {
            while !vad.isEmpty() { vad.pop() }
        }

        if let engine = audioEngine, !engine.isRunning {
            try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
            try engine.start()
        }
    }

    func stop() {
        guard activeSessionId != nil else { return }
        vad?.flush()
        drainVAD()
        expectedSegmentCount = nextSegmentOrder
        if nextSegmentOrder == 0 {
            finalize(merged: "")
        } else {
            checkAllSegmentsDecoded()
        }
        // NOTE: do NOT clear activeSessionId here — async decodes on decodeQueue
        // need it to match in handleSegmentResult. It is cleared in finalize().
        // NOTE: do NOT stop audioEngine — keep warm for next session (AirPods routing).
    }

    func teardown() {
        unregisterRouteChangeObserver()
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        converter = nil
        recognizer = nil
        vad = nil
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
        guard let engine = audioEngine, let outputFormat = outputFormat else { return }
        let input = engine.inputNode
        let newInputFormat = input.outputFormat(forBus: 0)
        guard newInputFormat.channelCount > 0 else { return }

        if let existing = converter,
           existing.inputFormat.sampleRate == newInputFormat.sampleRate,
           existing.inputFormat.channelCount == newInputFormat.channelCount {
            return
        }

        let wasRunning = engine.isRunning
        engine.stop()
        input.removeTap(onBus: 0)

        guard let newConverter = AVAudioConverter(from: newInputFormat, to: outputFormat) else { return }
        self.converter = newConverter

        input.installTap(onBus: 0, bufferSize: 4096, format: newInputFormat) { [weak self] buffer, _ in
            self?.handleInputBuffer(buffer)
        }

        if wasRunning {
            do {
                try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
                try engine.start()
            } catch {
                // The next start(sessionId:) will retry engine.start().
            }
        }
    }

    private func loadModelsIfNeeded() throws {
        guard recognizer == nil || vad == nil else { return }
        let resources = try SenseVoiceResources.bundled()
        let senseVoiceConfig = sherpaOnnxOfflineSenseVoiceModelConfig(model: resources.modelPath, language: "auto", useInverseTextNormalization: true)

        let modelConfig = sherpaOnnxOfflineModelConfig(
            tokens: resources.tokensPath,
            numThreads: 4,
            senseVoice: senseVoiceConfig
        )

        let featConfig = sherpaOnnxFeatureConfig(sampleRate: 16_000, featureDim: 80)
        var recognizerConfig = sherpaOnnxOfflineRecognizerConfig(featConfig: featConfig, modelConfig: modelConfig)
        recognizer = SherpaOnnxOfflineRecognizer(config: &recognizerConfig)

        let sileroConfig = sherpaOnnxSileroVadModelConfig(model: resources.vadPath, threshold: 0.5, minSilenceDuration: 0.8, minSpeechDuration: 0.25, windowSize: 512, maxSpeechDuration: 12.0)
        var vadConfig = sherpaOnnxVadModelConfig(sileroVad: sileroConfig, sampleRate: 16_000)
        vad = SherpaOnnxVoiceActivityDetectorWrapper(config: &vadConfig, buffer_size_in_seconds: 30)
    }

    private func configureAudioSessionAndEngine() throws {
        guard audioEngine == nil else { return }
        guard let outputFormat = outputFormat else { throw SenseVoiceError.invalidInputFormat }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetoothHFP])
        // Do NOT call setPreferredSampleRate(16_000): AirPods over HFP cannot honor it
        // and the resulting route renegotiation breaks input capture. Convert in software instead.
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.channelCount > 0 else { throw SenseVoiceError.audioEngineUnavailable }
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else { throw SenseVoiceError.invalidInputFormat }
        self.audioEngine = engine
        self.converter = converter

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.handleInputBuffer(buffer)
        }
        engine.prepare()
        try engine.start()
    }

    private func handleInputBuffer(_ buffer: AVAudioPCMBuffer) {
        guard activeSessionId != nil,
              let converter = self.converter,
              let outputFormat = self.outputFormat else { return }

        var consumed = false
        let inputBlock: AVAudioConverterInputBlock = { _, status in
            if consumed { status.pointee = .noDataNow; return nil }
            consumed = true
            status.pointee = .haveData
            return buffer
        }

        let frameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * outputFormat.sampleRate / buffer.format.sampleRate) + 1
        guard let converted = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: frameCapacity) else { return }
        var error: NSError?
        converter.convert(to: converted, error: &error, withInputFrom: inputBlock)
        let samples = converted.floatArray()
        if !samples.isEmpty {
            self.vad?.acceptWaveform(samples: samples)
            self.drainVAD()
        }
    }

    private func drainVAD() {
        guard let vad = vad, let sessionId = activeSessionId else { return }
        while !vad.isEmpty() {
            let seg = vad.front()
            let segSamples = seg.samples
            vad.pop()
            let order = nextSegmentOrder
            nextSegmentOrder += 1
            sessionAudioSeconds += Double(segSamples.count) / 16_000.0
            enqueueSegmentDecode(samples: segSamples, sessionId: sessionId, order: order)
        }
    }

    private func enqueueSegmentDecode(samples: [Float], sessionId: String, order: Int) {
        guard let recognizer = recognizer else { return }
        decodeQueue.async { [weak self] in
            let decodeStart = CFAbsoluteTimeGetCurrent()
            let result = recognizer.decode(samples: samples, sampleRate: 16_000)
            let decodeSeconds = CFAbsoluteTimeGetCurrent() - decodeStart
            let text = result.text
            DispatchQueue.main.async {
                self?.handleSegmentResult(sessionId: sessionId, order: order, text: text, decodeSeconds: decodeSeconds)
            }
        }
    }

    private func handleSegmentResult(sessionId: String, order: Int, text: String, decodeSeconds: Double) {
        guard sessionId == activeSessionId else { return }
        decodedSegments[order] = text.trimmingCharacters(in: .whitespacesAndNewlines)
        sessionDecodeCpuSeconds += decodeSeconds
        checkAllSegmentsDecoded()
    }

    private func checkAllSegmentsDecoded() {
        guard let expected = expectedSegmentCount,
              decodedSegments.count >= expected else { return }
        let merged = (0..<expected)
            .compactMap { decodedSegments[$0] }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        finalize(merged: merged)
    }

    private func finalize(merged: String) {
        let wallSeconds = CFAbsoluteTimeGetCurrent() - sessionWallStart
        let rtf = sessionAudioSeconds > 0 ? sessionDecodeCpuSeconds / sessionAudioSeconds : 0

        let metrics = ASRMetrics(
            audioDuration: sessionAudioSeconds,
            cpuDuration: sessionDecodeCpuSeconds,
            wallDuration: wallSeconds,
            rtf: rtf
        )

        let result = ASRResult(text: merged, isFinal: true, metrics: metrics)
        continuation.yield(result)

        activeSessionId = nil
        decodedSegments.removeAll()
        expectedSegmentCount = nil
    }
}
