import CoreFoundation
import Foundation
import os

public final class SherpaOnnxASREngine: ASREngine {
    public let name = "Sherpa-Onnx (SenseVoice)"

    private final class PendingFinalization {
        let result: ASRResult
        var recognizer: SherpaOnnxOfflineRecognizer?
        var vad: SherpaOnnxVoiceActivityDetectorWrapper?

        init(
            result: ASRResult,
            recognizer: SherpaOnnxOfflineRecognizer?,
            vad: SherpaOnnxVoiceActivityDetectorWrapper?
        ) {
            self.result = result
            self.recognizer = recognizer
            self.vad = vad
        }
    }

    private static let lifecycleLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.openwhispr.Stet",
        category: "SenseVoiceLifecycle"
    )

    private var recognizer: SherpaOnnxOfflineRecognizer?
    private var vad: SherpaOnnxVoiceActivityDetectorWrapper?
    private let audioCapture: any ASRAudioCapturing
    private let decodeQueue = DispatchQueue(label: "com.stet.StetASR.SherpaOnnxASREngine.decode")
    private let lock = NSRecursiveLock()
    private var preLoadBuffer: [Float] = []

    private var activeSessionId: String?
    private var nextSegmentOrder: Int = 0
    private var decodedSegments: [Int: String] = [:]
    private var expectedSegmentCount: Int?
    private var sessionAudioSeconds: Double = 0
    private var sessionDecodeCpuSeconds: Double = 0
    private var sessionWallStart: CFAbsoluteTime = 0
    private var shouldLogFirstDecodeAfterLoad = false

    public let resultStream: AsyncStream<ASRResult>
    private let continuation: AsyncStream<ASRResult>.Continuation

    private let modelManager: ASRModelManager
    public var onVolumeUpdate: ((Float) -> Void)?

    public convenience init(modelManager: ASRModelManager) {
        self.init(
            modelManager: modelManager,
            audioCapture: PersistentASRAudioCapture(strategy: .builtInPreferred)
        )
    }

    init(
        modelManager: ASRModelManager,
        audioCapture: any ASRAudioCapturing
    ) {
        let (stream, cont) = AsyncStream<ASRResult>.makeStream()
        self.resultStream = stream
        self.continuation = cont
        self.modelManager = modelManager
        self.audioCapture = audioCapture
    }

    public func prepare() async throws {
        try await audioCapture.prepare()
    }

    public func start(sessionId: String) async throws {
        try await loadModelsIfNeeded()
        beginSession(sessionId: sessionId)
        do {
            try await audioCapture.start { [weak self] result in
                self?.handleAudioFrameResult(result)
            }
        } catch {
            clearActiveSession()
            throw error
        }
    }

    private func beginSession(sessionId: String) {
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
    }

    public func stop() {
        audioCapture.stop()
        lock.lock()
        guard activeSessionId != nil else {
            lock.unlock()
            return
        }
        vad?.flush()
        drainVAD()
        expectedSegmentCount = nextSegmentOrder
        let finalization: PendingFinalization?
        if nextSegmentOrder == 0 {
            finalization = makeFinalizationLocked(merged: "")
        } else {
            finalization = makeFinalizationIfReadyLocked()
        }
        lock.unlock()

        if let finalization {
            completeFinalization(finalization)
        }
    }

    public func resetAudio() async throws {
        audioCapture.stop()
        clearActiveSession()
        try await audioCapture.reset()
    }

    private func clearActiveSession() {
        lock.lock()
        defer { lock.unlock() }

        activeSessionId = nil
        preLoadBuffer.removeAll()
        decodedSegments.removeAll()
        expectedSegmentCount = nil
        if let vad {
            while !vad.isEmpty() { vad.pop() }
        }
    }

    public func teardown() {
        audioCapture.teardown()
        recognizer = nil
        vad = nil
        activeSessionId = nil
        continuation.finish()
    }

    private func loadModelsIfNeeded() async throws {
        guard modelsNeedLoading() else {
            Self.lifecycleLogger.debug("event=model_load_skipped reason=already_loaded")
            return
        }

        let totalStart = ProcessInfo.processInfo.systemUptime
        Self.lifecycleLogger.info("event=model_load_started")

        let resolutionStart = ProcessInfo.processInfo.systemUptime
        let urls = try await modelManager.resolveModelURLs(for: "SenseVoice")
        let resolutionMilliseconds = Self.elapsedMilliseconds(since: resolutionStart)
        Self.lifecycleLogger.info(
            "event=model_assets_resolved duration_ms=\(resolutionMilliseconds, privacy: .public)"
        )
        guard let modelURL = urls["model"], let tokensURL = urls["tokens"], let vadURL = urls["vad"] else {
            throw NSError(
                domain: "StetASR", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Missing model paths from ModelManager"])
        }

        guard installModelsIfNeeded(modelURL: modelURL, tokensURL: tokensURL, vadURL: vadURL) else {
            Self.lifecycleLogger.debug("event=model_load_skipped reason=concurrent_load_completed")
            return
        }

        let totalMilliseconds = Self.elapsedMilliseconds(since: totalStart)
        Self.lifecycleLogger.info(
            "event=model_load_completed duration_ms=\(totalMilliseconds, privacy: .public)"
        )
    }

    private func modelsNeedLoading() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return recognizer == nil || vad == nil
    }

    private func installModelsIfNeeded(modelURL: URL, tokensURL: URL, vadURL: URL) -> Bool {
        lock.lock()
        let needsLoading = recognizer == nil || vad == nil
        lock.unlock()
        guard needsLoading else { return false }

        let senseVoiceConfig = sherpaOnnxOfflineSenseVoiceModelConfig(
            model: modelURL.path, language: "auto", useInverseTextNormalization: true)

        let modelConfig = sherpaOnnxOfflineModelConfig(
            tokens: tokensURL.path,
            numThreads: 4,
            senseVoice: senseVoiceConfig
        )

        let featConfig = sherpaOnnxFeatureConfig(sampleRate: 16_000, featureDim: 80)
        var recognizerConfig = sherpaOnnxOfflineRecognizerConfig(featConfig: featConfig, modelConfig: modelConfig)
        let recognizerStart = ProcessInfo.processInfo.systemUptime
        let loadedRecognizer = SherpaOnnxOfflineRecognizer(config: &recognizerConfig)
        let recognizerMilliseconds = Self.elapsedMilliseconds(since: recognizerStart)

        let sileroConfig = sherpaOnnxSileroVadModelConfig(
            model: vadURL.path, threshold: 0.5, minSilenceDuration: 0.5, minSpeechDuration: 0.25, windowSize: 512,
            maxSpeechDuration: 12.0)
        var vadConfig = sherpaOnnxVadModelConfig(sileroVad: sileroConfig, sampleRate: 16_000)
        let vadStart = ProcessInfo.processInfo.systemUptime
        let loadedVAD = SherpaOnnxVoiceActivityDetectorWrapper(config: &vadConfig, buffer_size_in_seconds: 30)
        let vadMilliseconds = Self.elapsedMilliseconds(since: vadStart)

        lock.lock()
        guard recognizer == nil || vad == nil else {
            lock.unlock()
            return false
        }
        recognizer = loadedRecognizer
        vad = loadedVAD
        shouldLogFirstDecodeAfterLoad = true
        lock.unlock()

        Self.lifecycleLogger.info(
            "event=recognizer_loaded duration_ms=\(recognizerMilliseconds, privacy: .public)"
        )
        Self.lifecycleLogger.info(
            "event=vad_loaded duration_ms=\(vadMilliseconds, privacy: .public)"
        )
        return true
    }

    private static func elapsedMilliseconds(since start: TimeInterval) -> String {
        String(format: "%.1f", (ProcessInfo.processInfo.systemUptime - start) * 1_000)
    }

    private func handleAudioFrameResult(
        _ result: Result<ASRAudioFrame, ASRAudioCaptureError>
    ) {
        switch result {
        case .success(let frame):
            handleAudioFrame(frame)
        case .failure(let error):
            Self.lifecycleLogger.error(
                "event=audio_capture_failed error=\(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func handleAudioFrame(_ frame: ASRAudioFrame) {
        lock.lock()
        guard let sessionId = activeSessionId else {
            lock.unlock()
            return
        }
        lock.unlock()

        guard !frame.samples.isEmpty else { return }
        lock.lock()
        guard activeSessionId == sessionId else {
            lock.unlock()
            return
        }
        if let vad {
            if !preLoadBuffer.isEmpty {
                vad.acceptWaveform(samples: preLoadBuffer)
                preLoadBuffer.removeAll()
            }
            vad.acceptWaveform(samples: frame.samples)
            drainVAD()
        } else {
            preLoadBuffer.append(contentsOf: frame.samples)
        }
        lock.unlock()

        onVolumeUpdate?(frame.level)
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
        let isFirstDecodeAfterLoad = claimFirstDecodeAfterLoad()
        decodeQueue.async { [weak self] in
            let decodeStart = ProcessInfo.processInfo.systemUptime
            let result = recognizer.decode(samples: samples, sampleRate: 16_000)
            let decodeSeconds = ProcessInfo.processInfo.systemUptime - decodeStart
            let text = result.text
            if isFirstDecodeAfterLoad {
                let decodeMilliseconds = String(format: "%.1f", decodeSeconds * 1_000)
                let audioMilliseconds = String(format: "%.1f", Double(samples.count) / 16.0)
                Self.lifecycleLogger.info(
                    "event=first_decode_completed duration_ms=\(decodeMilliseconds, privacy: .public) audio_ms=\(audioMilliseconds, privacy: .public)"
                )
            }
            DispatchQueue.main.async {
                self?.handleSegmentResult(sessionId: sessionId, order: order, text: text, decodeSeconds: decodeSeconds)
            }
        }
    }

    private func claimFirstDecodeAfterLoad() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let shouldLog = shouldLogFirstDecodeAfterLoad
        shouldLogFirstDecodeAfterLoad = false
        return shouldLog
    }

    private func handleSegmentResult(sessionId: String, order: Int, text: String, decodeSeconds: Double) {
        lock.lock()
        guard sessionId == activeSessionId else {
            lock.unlock()
            return
        }
        decodedSegments[order] = text.trimmingCharacters(in: .whitespacesAndNewlines)
        sessionDecodeCpuSeconds += decodeSeconds
        let finalization = makeFinalizationIfReadyLocked()
        lock.unlock()

        if let finalization {
            completeFinalization(finalization)
        }
    }

    private func makeFinalizationIfReadyLocked() -> PendingFinalization? {
        guard let expected = expectedSegmentCount,
            decodedSegments.count >= expected
        else { return nil }
        let merged = (0..<expected)
            .compactMap { decodedSegments[$0] }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return makeFinalizationLocked(merged: merged)
    }

    private func makeFinalizationLocked(merged: String) -> PendingFinalization? {
        guard let sessionId = activeSessionId else { return nil }
        let wallSeconds = CFAbsoluteTimeGetCurrent() - sessionWallStart
        let rtf = sessionAudioSeconds > 0 ? sessionDecodeCpuSeconds / sessionAudioSeconds : 0

        let metrics = ASRMetrics(
            audioDuration: sessionAudioSeconds,
            cpuDuration: sessionDecodeCpuSeconds,
            wallDuration: wallSeconds,
            rtf: rtf
        )

        let result = ASRResult(
            sessionId: sessionId,
            text: merged,
            isFinal: true,
            metrics: metrics
        )

        activeSessionId = nil
        decodedSegments.removeAll()
        expectedSegmentCount = nil
        preLoadBuffer.removeAll(keepingCapacity: false)
        shouldLogFirstDecodeAfterLoad = false

        let finalization = PendingFinalization(
            result: result,
            recognizer: recognizer,
            vad: vad
        )
        recognizer = nil
        vad = nil
        return finalization
    }

    private func completeFinalization(_ finalization: PendingFinalization) {
        let didReleaseModels = finalization.recognizer != nil || finalization.vad != nil
        let releaseStart = ProcessInfo.processInfo.systemUptime
        finalization.recognizer = nil
        finalization.vad = nil
        if didReleaseModels {
            let releaseMilliseconds = Self.elapsedMilliseconds(since: releaseStart)
            Self.lifecycleLogger.info(
                "event=models_unloaded duration_ms=\(releaseMilliseconds, privacy: .public)"
            )
        }

        continuation.yield(finalization.result)
    }
}
