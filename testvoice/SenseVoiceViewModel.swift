import AVFoundation
import Combine
import CoreFoundation
import Foundation
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

    private var recognizer: SherpaOnnxOfflineRecognizer?
    private var vad: SherpaOnnxVoiceActivityDetectorWrapper?
    private var audioEngine: AVAudioEngine?
    private var converter: AVAudioConverter?
    private let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)
    private let decodeQueue = DispatchQueue(label: "SenseVoiceDecodeQueue")
    
    private var accumulatedSamples: [Float] = []
    private var commandPollingTimer: Timer?
    private var activeSessionId: String?

    var isRecording: Bool {
        state == .recording
    }

    init() {
        Task { @MainActor in
            await self.bootstrap()
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
        guard url.scheme == "testvoice", url.host == "dictate" else { return false }
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
        accumulatedSamples.removeAll()
        activeSessionId = sessionId
        state = .recording
        partialStatus = "Recording... release mic to decode."
        let session = DictationSession(
            sessionId: sessionId,
            createdAt: Date(),
            updatedAt: Date(),
            state: .recording
        )
        SharedDictationManager.shared.saveSession(session)
    }

    private func stopAccumulatingAndDecode() {
        // Flip out of .recording before kicking off decode so the tap callback
        // stops appending samples and polling won't re-fire on .requestStop.
        state = .idle
        partialStatus = "Decoding..."
        SharedDictationManager.shared.updateState(.transcribing)
        decodeBatch()
    }

    private func decodeBatch() {
        guard let recognizer = recognizer, !accumulatedSamples.isEmpty else {
            state = .idle
            partialStatus = "No audio recorded."
            return
        }
        
        let samples = accumulatedSamples
        decodeQueue.async { [weak self] in
            let audioSeconds = Double(samples.count) / 16_000.0
            let decodeStart = CFAbsoluteTimeGetCurrent()
            let result = recognizer.decode(samples: samples, sampleRate: 16_000)
            let decodeSeconds = CFAbsoluteTimeGetCurrent() - decodeStart
            let rtf = audioSeconds > 0 ? decodeSeconds / audioSeconds : 0
            
            Task { @MainActor in
                guard let self else { return }
                let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                let language = result.lang
                if text.isEmpty {
                    self.partialStatus = "Empty result."
                    SharedDictationManager.shared.updateState(.ready)
                } else {
                    let prefix = language.isEmpty ? "" : "[\(language)] "
                    self.transcript = "\(prefix)\(text)"
                    self.partialStatus = "Finished."
                    SharedDictationManager.shared.updateText(partial: text, final: text)
                    SharedDictationManager.shared.updateState(.ready)
                }
                self.metricsText = String(format: "Batch Result: audio %.2fs, decode %.2fs, RTF %.2f", audioSeconds, decodeSeconds, rtf)
                self.state = .idle
            }
        }
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
            }
        }
    }
}

// MARK: - Shared Dictation Manager

enum DictationState: String, Codable {
    case idle
    case launching
    case warming
    case recording
    case transcribing
    case ready
    case inserted
    case cancelled
    case failed
    case timeout
    
    // Commands from keyboard to background app
    case requestStart
    case requestStop
}

struct DictationSession: Codable {
    let sessionId: String
    let createdAt: Date
    var updatedAt: Date
    var state: DictationState
    var partialText: String = ""
    var finalText: String = ""
    var revision: Int = 0
    var error: String?
}

class SharedDictationManager {
    static let shared = SharedDictationManager()
    private let appGroupIdentifier = "group.NaichengDeng.testvoice"
    private let sessionKey = "dictation.session"
    
    private var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }
    
    func saveSession(_ session: DictationSession) {
        if let data = try? JSONEncoder().encode(session) {
            defaults?.set(data, forKey: sessionKey)
            defaults?.synchronize()
        }
    }
    
    func getSession() -> DictationSession? {
        guard let data = defaults?.data(forKey: sessionKey) else { return nil }
        return try? JSONDecoder().decode(DictationSession.self, from: data)
    }
    
    func updateState(_ state: DictationState, error: String? = nil) {
        var session = getSession() ?? DictationSession(sessionId: UUID().uuidString, createdAt: Date(), updatedAt: Date(), state: .idle)
        session.state = state
        session.updatedAt = Date()
        session.error = error
        saveSession(session)
    }
    
    func updateError(_ error: String) {
        guard var session = getSession() else { return }
        session.error = error
        saveSession(session)
    }
    
    func updateText(partial: String, final: String) {
        guard var session = getSession() else { return }
        session.partialText = partial
        session.finalText = final
        session.revision += 1
        session.updatedAt = Date()
        saveSession(session)
    }
    
    func clearSession() {
        defaults?.removeObject(forKey: sessionKey)
        defaults?.synchronize()
    }
}
