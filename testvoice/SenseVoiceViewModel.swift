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
    @Published private(set) var partialStatus = "Put SenseVoice/model.int8.onnx and SenseVoice/tokens.txt in the app bundle."
    @Published private(set) var metricsText = "RTF metrics will appear after decoding."

    private var recognizer: SherpaOnnxOfflineRecognizer?
    private var audioEngine: AVAudioEngine?
    private var converter: AVAudioConverter?
    private let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)
    private let decodeQueue = DispatchQueue(label: "SenseVoiceDecodeQueue")
    
    // Batch processing buffer
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
            partialStatus = "Recording... Tap Stop to decode the entire audio."
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
            state = .loading // Transition to loading while decoding
            partialStatus = "Decoding entire audio..."
            decodeBatch()
        } else if case .failed = state {
            // keep failed state
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
            
            // Decode the entire buffer
            let result = recognizer.decode(samples: samples, sampleRate: 16_000)
            
            let decodeSeconds = CFAbsoluteTimeGetCurrent() - decodeStart
            let rtf = audioSeconds > 0 ? decodeSeconds / audioSeconds : 0
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let language = result.lang
            
            print(String(format: "[SenseVoiceMetrics] Batch: audio_seconds=%.3f decode_seconds=%.3f rtf=%.3f text_chars=%d", audioSeconds, decodeSeconds, rtf, text.count))
            
            Task { @MainActor in
                guard let self else { return }
                if text.isEmpty {
                    self.partialStatus = "Decoded result is empty."
                } else {
                    let prefix = language.isEmpty ? "" : "[\(language)] "
                    self.transcript = "\(prefix)\(text)"
                    self.partialStatus = "Decoding finished."
                }
                
                self.metricsText = String(
                    format: "Batch: audio %.2fs, decode %.2fs, RTF %.2f",
                    audioSeconds, decodeSeconds, rtf
                )
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
        guard recognizer == nil else { return }
        let loadStart = CFAbsoluteTimeGetCurrent()
        let resources = try SenseVoiceResources.bundled()
        let senseVoiceConfig = sherpaOnnxOfflineSenseVoiceModelConfig(
            model: resources.modelPath,
            language: "auto",
            useInverseTextNormalization: true
        )
        let modelConfig = sherpaOnnxOfflineModelConfig(
            tokens: resources.tokensPath,
            senseVoice: senseVoiceConfig,
            numThreads: 4 // Use more threads for batch processing
        )
        let featConfig = sherpaOnnxFeatureConfig(sampleRate: 16_000, featureDim: 80)
        var recognizerConfig = sherpaOnnxOfflineRecognizerConfig(
            featConfig: featConfig,
            modelConfig: modelConfig
        )
        recognizer = SherpaOnnxOfflineRecognizer(config: &recognizerConfig)

        let loadSeconds = CFAbsoluteTimeGetCurrent() - loadStart
        metricsText = String(format: "Model load: %.3fs", loadSeconds)
        print(String(format: "[SenseVoiceMetrics] model_load_seconds=%.3f", loadSeconds))
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
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw SenseVoiceError.invalidInputFormat
        }
        self.audioEngine = engine
        self.converter = converter

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.handleInputBuffer(buffer)
        }
        engine.prepare()
    }

    nonisolated private func handleInputBuffer(_ buffer: AVAudioPCMBuffer) {
        // Run conversion on a background thread to avoid blocking audio thread or main thread
        guard let converter = self.converter, let outputFormat = self.outputFormat else { return }
        
        var consumed = false
        let inputBlock: AVAudioConverterInputBlock = { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        
        let frameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * outputFormat.sampleRate / buffer.format.sampleRate) + 1
        guard let converted = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: frameCapacity) else { return }
        
        var error: NSError?
        converter.convert(to: converted, error: &error, withInputFrom: inputBlock)
        
        let samples = converted.floatArray()
        guard !samples.isEmpty else { return }
        
        Task { @MainActor [weak self] in
            guard let self = self, self.isRecording else { return }
            self.accumulatedSamples.append(contentsOf: samples)
        }
    }
}
