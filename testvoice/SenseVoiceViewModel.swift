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
    @Published private(set) var metricsText = "RTF metrics will appear after the first decoded segment."

    private var recognizer: SherpaOnnxOfflineRecognizer?
    private var vad: SherpaOnnxVoiceActivityDetectorWrapper?
    private var audioEngine: AVAudioEngine?
    private var converter: AVAudioConverter?
    private let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)
    private let decodeQueue = DispatchQueue(label: "SenseVoiceDecodeQueue")
    private var decodedAudioSeconds: Double = 0
    private var decodeWallSeconds: Double = 0
    private var decodedSegmentCount = 0

    var isRecording: Bool {
        state == .recording
    }

    func toggleRecording() {
        if isRecording {
            stopRecording(flush: true)
        } else {
            Task { await startRecording() }
        }
    }

    func clearTranscript() {
        transcript = ""
    }

    private func startRecording() async {
        state = .loading
        do {
            try await requestMicrophonePermission()
            try loadModelsIfNeeded()
            try configureAudioEngine()
            try audioEngine?.start()
            partialStatus = "Recording. Speak a sentence and pause to trigger VAD."
            state = .recording
        } catch {
            state = .failed(error.localizedDescription)
            partialStatus = error.localizedDescription
            stopRecording(flush: false)
        }
    }

    private func stopRecording(flush: Bool) {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        converter = nil
        if flush {
            vad?.flush()
            decodeAvailableSegments()
        }
        if case .failed = state {
            return
        }
        state = .idle
        partialStatus = transcript.isEmpty ? "Stopped. No speech segment decoded yet." : "Stopped."
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
        let loadStart = CFAbsoluteTimeGetCurrent()
        let resources = try SenseVoiceResources.bundled()
        let senseVoiceConfig = sherpaOnnxOfflineSenseVoiceModelConfig(
            model: resources.modelPath,
            language: "auto",
            useInverseTextNormalization: true
        )
        let modelConfig = sherpaOnnxOfflineModelConfig(
            tokens: resources.tokensPath,
            senseVoice: senseVoiceConfig
        )
        let featConfig = sherpaOnnxFeatureConfig(sampleRate: 16_000, featureDim: 80)
        var recognizerConfig = sherpaOnnxOfflineRecognizerConfig(
            featConfig: featConfig,
            modelConfig: modelConfig
        )
        recognizer = SherpaOnnxOfflineRecognizer(config: &recognizerConfig)

        let sileroConfig = sherpaOnnxSileroVadModelConfig(
            model: resources.vadPath,
            threshold: 0.5,
            minSilenceDuration: 0.5,
            minSpeechDuration: 0.25,
            windowSize: 512,
            maxSpeechDuration: 12.0
        )
        var vadConfig = sherpaOnnxVadModelConfig(sileroVad: sileroConfig, sampleRate: 16_000)
        vad = SherpaOnnxVoiceActivityDetectorWrapper(config: &vadConfig, buffer_size_in_seconds: 30)

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

        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.handleInputBuffer(buffer)
        }
        engine.prepare()
    }

    nonisolated private func handleInputBuffer(_ buffer: AVAudioPCMBuffer) {
        Task { @MainActor [weak self] in
            guard let self, let converter = self.converter, let outputFormat = self.outputFormat else { return }
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
            self.vad?.acceptWaveform(samples: samples)
            self.decodeAvailableSegments()
            if self.vad?.isSpeechDetected() == true {
                self.partialStatus = "Speech detected..."
            }
        }
    }

    private func decodeAvailableSegments() {
        guard let vad, let recognizer else { return }
        while !vad.isEmpty() {
            let segment = vad.front()
            let samples = segment.samples
            vad.pop()
            decodeQueue.async { [weak self] in
                let audioSeconds = Double(samples.count) / 16_000.0
                let decodeStart = CFAbsoluteTimeGetCurrent()
                let result = recognizer.decode(samples: samples, sampleRate: 16_000)
                let decodeSeconds = CFAbsoluteTimeGetCurrent() - decodeStart
                let rtf = audioSeconds > 0 ? decodeSeconds / audioSeconds : 0
                let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                let language = result.lang
                print(String(format: "[SenseVoiceMetrics] segment=%d audio_seconds=%.3f decode_seconds=%.3f rtf=%.3f text_chars=%d", samples.count, audioSeconds, decodeSeconds, rtf, text.count))
                Task { @MainActor in
                    guard let self else { return }
                    if text.isEmpty {
                        self.partialStatus = "Decoded an empty segment."
                        return
                    }
                    self.decodedSegmentCount += 1
                    self.decodedAudioSeconds += audioSeconds
                    self.decodeWallSeconds += decodeSeconds
                    let averageRTF = self.decodedAudioSeconds > 0 ? self.decodeWallSeconds / self.decodedAudioSeconds : 0
                    let prefix = language.isEmpty ? "" : "[\(language)] "
                    self.transcript += self.transcript.isEmpty ? "\(prefix)\(text)" : "\n\(prefix)\(text)"
                    self.partialStatus = "Last segment decoded."
                    self.metricsText = String(
                        format: "Last: audio %.2fs, decode %.2fs, RTF %.2f\nAvg: audio %.2fs, decode %.2fs, RTF %.2f, segments %d",
                        audioSeconds, decodeSeconds, rtf,
                        self.decodedAudioSeconds, self.decodeWallSeconds, averageRTF, self.decodedSegmentCount
                    )
                }
            }
        }
    }
}
