import AVFoundation
import Combine
import CoreFoundation
import Foundation
import StetRewrite
import StetAI
import StetCore
import UIKit

@MainActor
final class SenseVoiceViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case loading
        case recording
        case warming
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var transcript = ""
    @Published private(set) var partialStatus = "Put SenseVoice/model.int8.onnx, SenseVoice/tokens.txt, and Vad/silero_vad.onnx in the app bundle."
    @Published private(set) var metricsText = "RTF metrics will appear after decoding."
    @Published var isExternalLaunch: Bool = false
    
    func dismissExternalGuide() {
        isExternalLaunch = false
    }

    private var recognizer: SherpaOnnxOfflineRecognizer?
    private var vad: SherpaOnnxVoiceActivityDetectorWrapper?
    private var audioEngine: AVAudioEngine?
    private var converter: AVAudioConverter?
    private let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)
    private let decodeQueue = DispatchQueue(label: "SenseVoiceDecodeQueue")
    private let rewriteSettingsStore: RewriteSettingsStore
    
    private var commandPollingTimer: Timer?
    private var activeSessionId: String?

    // Per-session segment tracking (VAD-driven chunked decode)
    private var nextSegmentOrder: Int = 0
    private var decodedSegments: [Int: String] = [:]
    private var expectedSegmentCount: Int?
    private var sessionAudioSeconds: Double = 0
    private var sessionDecodeCpuSeconds: Double = 0
    private var sessionWallStart: CFAbsoluteTime = 0
    private var accumulatedSamples: [Float] = []

    var isRecording: Bool {
        state == .recording
    }

    init(rewriteSettingsStore: RewriteSettingsStore) {
        self.rewriteSettingsStore = rewriteSettingsStore
        Task { @MainActor in
            await self.bootstrap()
        }
        registerAudioSessionObservers()
    }

    func ensureMicAlive() {
        guard let engine = audioEngine else {
            Task { @MainActor in await bootstrap() }
            return
        }
        do {
            try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
            if !engine.isRunning {
                try engine.start()
            }
        } catch {
            SharedDictationManager.shared.updateState(.failed, error: error.localizedDescription)
        }
    }

    private func registerAudioSessionObservers() {
        let center = NotificationCenter.default
        center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard
                let info = note.userInfo,
                let typeRaw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                let type = AVAudioSession.InterruptionType(rawValue: typeRaw)
            else { return }
            if type == .ended {
                Task { @MainActor in self?.ensureMicAlive() }
            }
        }
        center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.ensureMicAlive() }
        }
    }

    private func bootstrap() async {
        state = .loading
        partialStatus = "Loading models and warming up audio engine..."
        do {
            try await requestMicrophonePermission()
            try loadModelsIfNeeded()
            try configureAudioEngine()
            try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
            try audioEngine?.start()
            state = .idle
            partialStatus = "Ready. Hold mic on keyboard to dictate."
            startCommandPolling()
            checkKeyboardCommands()
        } catch {
            state = .failed(error.localizedDescription)
            partialStatus = error.localizedDescription
            SharedDictationManager.shared.updateState(.failed, error: error.localizedDescription)
        }
    }

    func toggleRecording() {
        guard state != .loading, state != .warming else { return }
        if isRecording {
            stopAccumulatingAndDecode()
        } else {
            startAccumulating(sessionId: UUID().uuidString)
        }
    }

    func clearTranscript() {
        transcript = ""
    }

    @discardableResult
    func handleIncomingURL(_ url: URL) -> Bool {
        guard url.scheme == "stetmobile", url.host == "dictate" else { return false }
        isExternalLaunch = true
        // The polling timer will pick up any pending requestStart from the keyboard.
        checkKeyboardCommands()
        return true
    }

    private func startCommandPolling() {
        commandPollingTimer?.invalidate()
        commandPollingTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkKeyboardCommands()
            }
        }
    }

    private func checkKeyboardCommands() {
        SharedDictationManager.shared.heartbeat()
        guard let session = SharedDictationManager.shared.getSession() else { return }
        switch session.state {
        case .requestStart:
            if state == .idle {
                startAccumulating(sessionId: session.sessionId)
            }
        case .requestStop:
            if state == .recording {
                stopAccumulatingAndDecode()
            }
        default:
            break
        }
    }

    private func startAccumulating(sessionId: String) {
        // Discard any pre-session VAD output so this session starts clean.
        if let vad = vad {
            while !vad.isEmpty() { vad.pop() }
        }
        activeSessionId = sessionId
        nextSegmentOrder = 0
        decodedSegments.removeAll()
        expectedSegmentCount = nil
        sessionAudioSeconds = 0
        sessionDecodeCpuSeconds = 0
        accumulatedSamples.removeAll()
        state = .recording
        partialStatus = "Recording... tap mic again to decode."
        let session = DictationSession(
            sessionId: sessionId,
            createdAt: Date(),
            updatedAt: Date(),
            state: .recording
        )
        SharedDictationManager.shared.saveSession(session)
    }

    private func stopAccumulatingAndDecode() {
        guard let sessionId = activeSessionId else { return }
        // Flip out of .recording so handleInputBuffer's drainVAD won't enqueue
        // more segments for this session via the live path.
        state = .idle
        partialStatus = "Decoding..."
        SharedDictationManager.shared.updateState(.transcribing)
        sessionWallStart = CFAbsoluteTimeGetCurrent()

        // Force VAD to finalize any in-progress speech, then drain remaining
        // segments and submit them as the tail of this session.
        vad?.flush()
        drainVAD()
        expectedSegmentCount = nextSegmentOrder

        if nextSegmentOrder == 0 {
            finalize(merged: "")
        } else {
            checkAllSegmentsDecoded()
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
            Task { @MainActor [weak self] in
                self?.handleSegmentResult(
                    sessionId: sessionId,
                    order: order,
                    text: text,
                    decodeSeconds: decodeSeconds
                )
            }
        }
    }

    private func handleSegmentResult(sessionId: String, order: Int, text: String, decodeSeconds: Double) {
        // Discard results from stale sessions (user started a new one).
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
            .joined()
        finalize(merged: merged)
    }

    private func finalize(merged: String) {
        let wallSeconds = CFAbsoluteTimeGetCurrent() - sessionWallStart
        let rtf = sessionAudioSeconds > 0 ? sessionDecodeCpuSeconds / sessionAudioSeconds : 0

        if merged.isEmpty {
            partialStatus = "Empty result."
            SharedDictationManager.shared.updateState(.ready)
            finalizeMetricsAndReset(wallSeconds: wallSeconds, rtf: rtf)
            return
        }

        // Try AI rewrite if enabled, otherwise use raw transcript
        if let rewriteService = rewriteSettingsStore.makeRewriteServiceIfEnabled() {
            partialStatus = "Rewriting..."
            Task {
                let request = TextRewriteRequest.cleanup(merged, audience: .human)
                do {
                    let cleaned = try await rewriteService.rewrite(request)
                    self.transcript = cleaned
                    self.partialStatus = "Finished (rewritten)."
                    SharedDictationManager.shared.updateText(partial: cleaned, final: cleaned)
                } catch {
                    // Fallback: always preserve the raw transcript
                    self.transcript = merged
                    self.partialStatus = "Finished (rewrite failed, showing raw)."
                    SharedDictationManager.shared.updateText(partial: merged, final: merged)
                }
                SharedDictationManager.shared.updateState(.ready)
                self.finalizeMetricsAndReset(wallSeconds: wallSeconds, rtf: rtf)
            }
        } else {
            transcript = merged
            partialStatus = "Finished."
            SharedDictationManager.shared.updateText(partial: merged, final: merged)
            SharedDictationManager.shared.updateState(.ready)
            finalizeMetricsAndReset(wallSeconds: wallSeconds, rtf: rtf)
        }
    }

    private func finalizeMetricsAndReset(wallSeconds: Double, rtf: Double) {
        metricsText = String(
            format: "audio %.2fs, wall-after-stop %.2fs, cpu %.2fs, RTF %.2f, segs %d",
            sessionAudioSeconds, wallSeconds, sessionDecodeCpuSeconds, rtf, expectedSegmentCount ?? 0
        )
        activeSessionId = nil
        decodedSegments.removeAll()
        expectedSegmentCount = nil
        state = .idle
    }

    private func requestMicrophonePermission() async throws {
        if #available(iOS 17.0, *) {
            let granted = await AVAudioApplication.requestRecordPermission()
            if !granted { throw SenseVoiceError.microphoneDenied }
        } else {
            let granted = await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
            if !granted { throw SenseVoiceError.microphoneDenied }
        }
    }

    private func loadModelsIfNeeded() throws {
        guard recognizer == nil || vad == nil else { return }
        let resources = try SenseVoiceResources.bundled()
        let senseVoiceConfig = sherpaOnnxOfflineSenseVoiceModelConfig(model: resources.modelPath, language: "auto", useInverseTextNormalization: true)
        
        // Fix: numThreads must precede senseVoice per function signature
        let modelConfig = sherpaOnnxOfflineModelConfig(
            tokens: resources.tokensPath,
            numThreads: 4,
            senseVoice: senseVoiceConfig
        )
        
        let featConfig = sherpaOnnxFeatureConfig(sampleRate: 16_000, featureDim: 80)
        var recognizerConfig = sherpaOnnxOfflineRecognizerConfig(featConfig: featConfig, modelConfig: modelConfig)
        recognizer = SherpaOnnxOfflineRecognizer(config: &recognizerConfig)

        let sileroConfig = sherpaOnnxSileroVadModelConfig(model: resources.vadPath, threshold: 0.5, minSilenceDuration: 0.5, minSpeechDuration: 0.25, windowSize: 512, maxSpeechDuration: 12.0)
        var vadConfig = sherpaOnnxVadModelConfig(sileroVad: sileroConfig, sampleRate: 16_000)
        vad = SherpaOnnxVoiceActivityDetectorWrapper(config: &vadConfig, buffer_size_in_seconds: 30)
    }

    private func configureAudioEngine() throws {
        guard let outputFormat else { throw SenseVoiceError.invalidInputFormat }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setPreferredSampleRate(16_000)
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
    }

    nonisolated private func handleInputBuffer(_ buffer: AVAudioPCMBuffer) {
        Task { @MainActor [weak self] in
            guard let self = self, let converter = self.converter, let outputFormat = self.outputFormat, self.isRecording else { return }
            
            // Fix for Swift 6: Use a local variable to capture state if needed, 
            // but for simple conversion it should be fine within the Actor task.
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
                self.accumulatedSamples.append(contentsOf: samples)
                self.vad?.acceptWaveform(samples: samples)
                self.drainVAD()
            }
        }
    }
}


