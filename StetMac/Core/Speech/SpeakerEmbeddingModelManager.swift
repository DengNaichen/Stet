#if os(macOS)
    @preconcurrency import AVFoundation
    import CryptoKit
    import FluidAudio
    import Foundation
    import StetASR

    struct SpeakerEnrollmentEmbedding: Sendable {
        let model: SpeakerEmbeddingModelIdentity
        let normalizedVector: [Float]
    }

    enum SpeakerEmbeddingModelManagerError: LocalizedError {
        case invalidAudio
        case modelDirectoryUnavailable
        case modelDownloadFailed

        var errorDescription: String? {
            switch self {
            case .invalidAudio:
                return "The recording must contain at least 1.2 seconds of clear speech."
            case .modelDirectoryUnavailable:
                return "Stet could not resolve the speaker model directory."
            case .modelDownloadFailed:
                return "Stet could not download the speaker recognition model."
            }
        }
    }

    actor SpeakerEmbeddingModelManager {
        private static let modelFileName = "3dspeaker_speech_campplus_sv_zh-cn_16k-common.onnx"
        private static let modelDownloadURL = URL(
            string:
                "https://github.com/k2-fsa/sherpa-onnx/releases/download/speaker-recongition-models/\(modelFileName)"
        )!

        private var loadedRecognizer: SpeakerEmbeddingRecognizer?

        func recognizer() async throws -> SpeakerEmbeddingRecognizer {
            if let loadedRecognizer { return loadedRecognizer }

            let modelURL = try await Self.resolveModelURL()
            let data = try Data(contentsOf: modelURL, options: .mappedIfSafe)
            let revision = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            let recognizer = try SpeakerEmbeddingRecognizer(
                modelURL: modelURL,
                revision: revision
            )
            loadedRecognizer = recognizer
            return recognizer
        }

        private static func resolveModelURL() async throws -> URL {
            guard
                let applicationSupport = FileManager.default.urls(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask
                ).first
            else {
                throw SpeakerEmbeddingModelManagerError.modelDirectoryUnavailable
            }
            let directory =
                applicationSupport
                .appendingPathComponent("Stet", isDirectory: true)
                .appendingPathComponent("Models", isDirectory: true)
                .appendingPathComponent("SpeakerEmbedding", isDirectory: true)
            let destination = directory.appendingPathComponent(modelFileName)
            if FileManager.default.fileExists(atPath: destination.path) {
                return destination
            }

            let probeCache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
                .first?
                .appendingPathComponent("StetSpeakerProbe", isDirectory: true)
                .appendingPathComponent(modelFileName)
            if let probeCache, FileManager.default.fileExists(atPath: probeCache.path) {
                return probeCache
            }

            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let (temporaryURL, response) = try await URLSession.shared.download(from: modelDownloadURL)
            guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode) else {
                try? FileManager.default.removeItem(at: temporaryURL)
                throw SpeakerEmbeddingModelManagerError.modelDownloadFailed
            }
            do {
                try FileManager.default.moveItem(at: temporaryURL, to: destination)
            } catch {
                try? FileManager.default.removeItem(at: temporaryURL)
                throw error
            }
            return destination
        }
    }

    actor SpeakerEnrollmentEmbeddingService {
        private let modelManager: SpeakerEmbeddingModelManager

        init(modelManager: SpeakerEmbeddingModelManager = SpeakerEmbeddingModelManager()) {
            self.modelManager = modelManager
        }

        func extract(from recordingURL: URL) async throws -> SpeakerEnrollmentEmbedding {
            let samples = try Self.readNormalizedSamples(from: recordingURL)
            let segmentation = try await AudioSignalAnalyzer.segmentSpeechForVad(
                samples: samples,
                sampleRate: 16_000
            )
            let voicedSamples = Self.voicedSamples(from: segmentation)
            guard voicedSamples.count >= 19_200 else {
                throw SpeakerEmbeddingModelManagerError.invalidAudio
            }
            let recognizer = try await modelManager.recognizer()
            do {
                return SpeakerEnrollmentEmbedding(
                    model: recognizer.model,
                    normalizedVector: try await recognizer.extractEmbedding(from: voicedSamples)
                )
            } catch SpeakerEmbeddingRecognizerError.invalidEmbedding {
                throw SpeakerEmbeddingModelManagerError.invalidAudio
            }
        }

        nonisolated static func voicedSamples(
            from segmentation: AudioSignalAnalyzer.VadSegmentation
        ) -> [Float] {
            let sampleRate = Int(segmentation.sampleRate.rounded())
            return segmentation.segments.flatMap { segment -> ArraySlice<Float> in
                let start = max(0, min(segment.startSample(sampleRate: sampleRate), segmentation.samples.count))
                let end = max(start, min(segment.endSample(sampleRate: sampleRate), segmentation.samples.count))
                return segmentation.samples[start..<end]
            }
        }

        private static func readNormalizedSamples(from url: URL) throws -> [Float] {
            let file = try AVAudioFile(forReading: url)
            guard file.processingFormat.channelCount == 1,
                Int(file.processingFormat.sampleRate) == 16_000,
                let buffer = AVAudioPCMBuffer(
                    pcmFormat: file.processingFormat,
                    frameCapacity: AVAudioFrameCount(file.length)
                )
            else {
                throw SpeakerEmbeddingModelManagerError.invalidAudio
            }
            try file.read(into: buffer)
            let samples = MacNormalizedAudioSamples.samples(from: buffer)
            guard !samples.isEmpty else { throw SpeakerEmbeddingModelManagerError.invalidAudio }
            return samples
        }
    }
#endif
