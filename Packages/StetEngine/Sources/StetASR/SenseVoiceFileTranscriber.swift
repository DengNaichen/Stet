@preconcurrency import AVFoundation
import Foundation

public struct SenseVoiceFileTranscription: Sendable {
    public let text: String
    public let languageCode: String?

    public init(text: String, languageCode: String?) {
        self.text = text
        self.languageCode = languageCode
    }
}

public enum SenseVoiceFileTranscriberError: LocalizedError, Sendable {
    case audioFileMissing(URL)
    case audioPreparationFailed
    case recognizerInitializationFailed

    public var errorDescription: String? {
        switch self {
        case .audioFileMissing(let url):
            return "Audio file does not exist: \(url.path)"
        case .audioPreparationFailed:
            return "SenseVoice could not prepare the audio file."
        case .recognizerInitializationFailed:
            return "SenseVoice could not initialize the local recognizer."
        }
    }
}

/// Offline file transcription for macOS flows that already capture audio to a file.
///
/// The iOS keyboard uses `SherpaOnnxASREngine` for live audio. Both paths obtain
/// exactly the same SenseVoice assets through `SenseVoiceModelManager`.
public final class SenseVoiceFileTranscriber: @unchecked Sendable {
    private let modelManager: any ASRModelManager
    private let recognizerLock = NSLock()
    private var recognizer: SherpaOnnxOfflineRecognizer?
    private var loadedModelURL: URL?
    private var loadedTokensURL: URL?

    public init(modelManager: any ASRModelManager) {
        self.modelManager = modelManager
    }

    public func prewarm() async throws {
        try await prepareRecognizer()
    }

    public func transcribe(audioFileAt fileURL: URL, languageCode: String?) async throws -> SenseVoiceFileTranscription {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw SenseVoiceFileTranscriberError.audioFileMissing(fileURL)
        }

        let samples = try Self.readSamples(from: fileURL)
        try await prepareRecognizer()
        let result = try withRecognizer { recognizer in
            recognizer.decode(samples: samples, sampleRate: 16_000)
        }

        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return SenseVoiceFileTranscription(
            text: text,
            languageCode: Self.unwrapSpecialToken(result.lang) ?? languageCode
        )
    }

    private func modelURLs() async throws -> (model: URL, tokens: URL) {
        try await modelManager.downloadIfNeeded(for: SenseVoiceModelManager.modelName)
        let urls = try await modelManager.resolveModelURLs(for: SenseVoiceModelManager.modelName)
        guard let modelURL = urls[SenseVoiceModelAsset.model.key],
              let tokensURL = urls[SenseVoiceModelAsset.tokens.key] else {
            throw SenseVoiceFileTranscriberError.recognizerInitializationFailed
        }
        return (modelURL, tokensURL)
    }

    private func withRecognizer<T>(_ operation: (SherpaOnnxOfflineRecognizer) throws -> T) throws -> T {
        recognizerLock.lock()
        defer { recognizerLock.unlock() }

        guard let recognizer else {
            throw SenseVoiceFileTranscriberError.recognizerInitializationFailed
        }
        return try operation(recognizer)
    }

    private func configureRecognizer(modelURL: URL, tokensURL: URL) throws {
        recognizerLock.lock()
        defer { recognizerLock.unlock() }

        guard recognizer == nil || loadedModelURL != modelURL || loadedTokensURL != tokensURL else { return }

        let senseVoice = sherpaOnnxOfflineSenseVoiceModelConfig(
            model: modelURL.path,
            language: "auto",
            useInverseTextNormalization: true
        )
        let modelConfig = sherpaOnnxOfflineModelConfig(
            tokens: tokensURL.path,
            numThreads: max(1, min(4, ProcessInfo.processInfo.processorCount / 2)),
            senseVoice: senseVoice
        )
        let featureConfig = sherpaOnnxFeatureConfig(sampleRate: 16_000, featureDim: 80)
        var recognizerConfig = sherpaOnnxOfflineRecognizerConfig(
            featConfig: featureConfig,
            modelConfig: modelConfig
        )

        recognizer = SherpaOnnxOfflineRecognizer(config: &recognizerConfig)
        loadedModelURL = modelURL
        loadedTokensURL = tokensURL
    }

    private func prepareRecognizer() async throws {
        let urls = try await modelURLs()
        try configureRecognizer(modelURL: urls.model, tokensURL: urls.tokens)
    }

    private static func unwrapSpecialToken(_ value: String) -> String? {
        var normalized = value
        if normalized.hasPrefix("<|") { normalized.removeFirst(2) }
        if normalized.hasSuffix("|>") { normalized.removeLast(2) }
        return normalized.isEmpty ? nil : normalized
    }

    private static func readSamples(from fileURL: URL) throws -> [Float] {
        let inputFile = try AVAudioFile(forReading: fileURL)
        let inputFormat = inputFile.processingFormat
        let frameCount = AVAudioFrameCount(inputFile.length)

        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: frameCount) else {
            throw SenseVoiceFileTranscriberError.audioPreparationFailed
        }
        try inputFile.read(into: inputBuffer)

        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ) else {
            throw SenseVoiceFileTranscriberError.audioPreparationFailed
        }

        if inputFormat.channelCount == 1,
           inputFormat.commonFormat == .pcmFormatFloat32,
           Int(inputFormat.sampleRate) == 16_000,
           let channelData = inputBuffer.floatChannelData {
            return Array(UnsafeBufferPointer(start: channelData[0], count: Int(inputBuffer.frameLength)))
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat),
              let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: inputBuffer.frameLength) else {
            throw SenseVoiceFileTranscriberError.audioPreparationFailed
        }

        var conversionError: NSError?
        var suppliedInput = false
        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outputStatus in
            guard !suppliedInput else {
                outputStatus.pointee = .noDataNow
                return nil
            }
            suppliedInput = true
            outputStatus.pointee = .haveData
            return inputBuffer
        }

        guard status != .error,
              conversionError == nil,
              let channelData = outputBuffer.floatChannelData else {
            throw SenseVoiceFileTranscriberError.audioPreparationFailed
        }
        return Array(UnsafeBufferPointer(start: channelData[0], count: Int(outputBuffer.frameLength)))
    }
}
