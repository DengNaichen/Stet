import AVFoundation
import Combine
import CoreFoundation
import Foundation

@MainActor
final class SenseVoiceViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case loading
        case recording
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

    var isRecording: Bool {
        state == .recording
    }

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            Task { await startRecording() }
        }
    }

    func clearTranscript() {
        transcript = ""
    }

    private func startRecording() async {
        state = .loading
        accumulatedSamples.removeAll()
        do {
            try await requestMicrophonePermission()
            try loadModelsIfNeeded()
            try configureAudioEngine()
            try audioEngine?.start()
            partialStatus = "Recording... Tap Stop to decode."
            state = .recording
        } catch {
            state = .failed(error.localizedDescription)
            partialStatus = error.localizedDescription
            stopRecording()
        }
    }

    private func stopRecording() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        converter = nil
        
        if state == .recording {
            state = .loading
            partialStatus = "Decoding..."
            decodeBatch()
        } else if case .failed = state {
        } else {
            state = .idle
        }
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
                } else {
                    let prefix = language.isEmpty ? "" : "[\(language)] "
                    self.transcript = "\(prefix)\(text)"
                    self.partialStatus = "Finished."
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
