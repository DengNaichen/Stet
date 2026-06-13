import AVFoundation
import Foundation
import CoreFoundation

public final class SherpaOnnxASREngine: ASREngine {
    public let name = "Sherpa-Onnx (SenseVoice)"

    private var recognizer: SherpaOnnxOfflineRecognizer?
    private var vad: SherpaOnnxVoiceActivityDetectorWrapper?
    private var audioEngine: AVAudioEngine?
    private var converter: AVAudioConverter?
    private let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)
    private let decodeQueue = DispatchQueue(label: "com.stet.StetASR.SherpaOnnxASREngine.decode")
    private let lock = NSRecursiveLock()
    private var preLoadBuffer: [Float] = []

    private var activeSessionId: String?
    private var routeChangeObserver: NSObjectProtocol?
    private var nextSegmentOrder: Int = 0
    private var decodedSegments: [Int: String] = [:]
    private var expectedSegmentCount: Int?
    private var sessionAudioSeconds: Double = 0
    private var sessionDecodeCpuSeconds: Double = 0
    private var sessionWallStart: CFAbsoluteTime = 0

    public let resultStream: AsyncStream<ASRResult>
    private let continuation: AsyncStream<ASRResult>.Continuation
    
    private let modelManager: ASRModelManager
    public var onVolumeUpdate: ((Float) -> Void)?

    public init(modelManager: ASRModelManager) {
        let (stream, cont) = AsyncStream<ASRResult>.makeStream()
        self.resultStream = stream
        self.continuation = cont
        self.modelManager = modelManager
    }

    public func prepare() async throws {
        try configureAudioSessionAndEngine()
        try await loadModelsIfNeeded()
        registerRouteChangeObserver()
    }

    public func start(sessionId: String) async throws {
        if audioEngine == nil { try await prepare() }

        lock.lock()
        defer { lock.unlock() }

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
            #if os(iOS)
            try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
            #endif
            try engine.start()
        }
    }

    public func stop() {
        lock.lock()
        defer { lock.unlock() }
        guard activeSessionId != nil else { return }
        vad?.flush()
        drainVAD()
        expectedSegmentCount = nextSegmentOrder
        if nextSegmentOrder == 0 {
            finalize(merged: "")
        } else {
            checkAllSegmentsDecoded()
        }
    }

    public func teardown() {
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
        #if os(iOS)
        guard routeChangeObserver == nil else { return }
        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            self?.handleRouteChange(note)
        }
        #endif
    }

    private func unregisterRouteChangeObserver() {
        if let token = routeChangeObserver {
            NotificationCenter.default.removeObserver(token)
            routeChangeObserver = nil
        }
    }

    private func handleRouteChange(_ note: Notification) {
        #if os(iOS)
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
        #endif
    }

    private func loadModelsIfNeeded() async throws {
        lock.lock()
        defer { lock.unlock() }
        guard recognizer == nil || vad == nil else { return }
        
        let urls = try await modelManager.resolveModelURLs(for: "SenseVoice")
        guard let modelURL = urls["model"], let tokensURL = urls["tokens"], let vadURL = urls["vad"] else {
            throw NSError(domain: "StetASR", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing model paths from ModelManager"])
        }
        
        let senseVoiceConfig = sherpaOnnxOfflineSenseVoiceModelConfig(model: modelURL.path, language: "auto", useInverseTextNormalization: true)

        let modelConfig = sherpaOnnxOfflineModelConfig(
            tokens: tokensURL.path,
            numThreads: 4,
            senseVoice: senseVoiceConfig
        )

        let featConfig = sherpaOnnxFeatureConfig(sampleRate: 16_000, featureDim: 80)
        var recognizerConfig = sherpaOnnxOfflineRecognizerConfig(featConfig: featConfig, modelConfig: modelConfig)
        recognizer = SherpaOnnxOfflineRecognizer(config: &recognizerConfig)

        let sileroConfig = sherpaOnnxSileroVadModelConfig(model: vadURL.path, threshold: 0.5, minSilenceDuration: 0.5, minSpeechDuration: 0.25, windowSize: 512, maxSpeechDuration: 12.0)
        var vadConfig = sherpaOnnxVadModelConfig(sileroVad: sileroConfig, sampleRate: 16_000)
        vad = SherpaOnnxVoiceActivityDetectorWrapper(config: &vadConfig, buffer_size_in_seconds: 30)
    }

    private func configureAudioSessionAndEngine() throws {
        lock.lock()
        defer { lock.unlock() }
        guard audioEngine == nil else { return }
        guard let outputFormat = outputFormat else {
            throw NSError(domain: "StetASR", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid output format"])
        }

        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        #endif

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.channelCount > 0 else {
            throw NSError(domain: "StetASR", code: 3, userInfo: [NSLocalizedDescriptionKey: "Audio engine input unavailable"])
        }
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
             throw NSError(domain: "StetASR", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid input format"])
        }
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
            let sumSq = samples.reduce(0) { $0 + $1 * $1 }
            let rms = sqrt(sumSq / Float(samples.count))
            let level = min(rms * 15, 1.0)
            
            onVolumeUpdate?(level)
            
            lock.lock()
            defer { lock.unlock() }
            if let vad = self.vad {
                if !self.preLoadBuffer.isEmpty {
                    vad.acceptWaveform(samples: self.preLoadBuffer)
                    self.preLoadBuffer.removeAll()
                }
                vad.acceptWaveform(samples: samples)
                self.drainVAD()
            } else {
                self.preLoadBuffer.append(contentsOf: samples)
            }
        }
    }

    private func drainVAD() {
        lock.lock()
        defer { lock.unlock() }
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
        lock.lock()
        defer { lock.unlock() }
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
        lock.lock()
        defer { lock.unlock() }
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
