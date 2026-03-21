@preconcurrency import AVFoundation
import FluidAudio
import Foundation

protocol AudioPostProcessing: Sendable {
    func processAudioFile(at sourceURL: URL, duration: TimeInterval?) async throws -> AudioPostProcessingResult
}

struct AudioPostProcessingResult: Sendable {
    let url: URL
    let duration: TimeInterval?
    let cleanupURLs: [URL]
    let shouldDiscardAsNoSpeech: Bool

    static func passthrough(url: URL, duration: TimeInterval?) -> Self {
        Self(
            url: url,
            duration: duration,
            cleanupURLs: [url],
            shouldDiscardAsNoSpeech: false
        )
    }

    static func discard(url: URL, duration: TimeInterval?) -> Self {
        Self(
            url: url,
            duration: duration,
            cleanupURLs: [url],
            shouldDiscardAsNoSpeech: true
        )
    }
}

final class DefaultAudioPostProcessor: AudioPostProcessing, @unchecked Sendable {
    init(settingsStore _: DictationSettingsStore = DictationSettingsStore()) {}

    func processAudioFile(at sourceURL: URL, duration: TimeInterval?) async throws -> AudioPostProcessingResult {
        guard sourceURL.pathExtension.lowercased() == "wav" else {
            return .passthrough(url: sourceURL, duration: duration)
        }

        let samples: [Float]
        let fileSampleRate: Double
        do {
            // FluidAudio's AudioConverter facilitates loading and resampling.
            // We'll also retrieve the actual sample rate from the file for the analyzer.
            let audioFile = try AVAudioFile(forReading: sourceURL)
            fileSampleRate = audioFile.fileFormat.sampleRate
            samples = try AudioConverter().resampleAudioFile(sourceURL)
        } catch {
            AppLogger.warning(
                "Skipping audio post-processing because the audio file could not be loaded. error=\(error.localizedDescription)",
                category: .dictation
            )
            return .passthrough(url: sourceURL, duration: duration)
        }

        // Analyze the audio signal. We handle sample rate dynamically based on the file.
        // Note: If AudioConverter is known to always resample to 16kHz, 16000 could be used directly.
        let analysis = try await AudioSignalAnalyzer.analyze(
            samples: samples,
            sampleRate: fileSampleRate
        )

        AppLogger.info(
            "Audio post-processing analyzed capture. \(analysis.summaryLine)",
            category: .dictation
        )
        if UserDefaults.standard.bool(forKey: MacPreferences.dictationPerfTracingEnabled) {
            AppLogger.warning(
                "Audio post-processing summary. \(analysis.summaryLine)",
                category: .dictation
            )
        }

        if analysis.shouldDiscardAsNoSpeech {
            AppLogger.warning(
                "Discarding capture as no speech was detected. \(analysis.summaryLine)",
                category: .dictation
            )
            return .discard(url: sourceURL, duration: duration)
        }

        return .passthrough(url: sourceURL, duration: duration)
    }
}
