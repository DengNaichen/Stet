@preconcurrency import AVFoundation
import FluidAudio
import Foundation

final class DefaultAudioPostProcessor: AudioPostProcessing, @unchecked Sendable {
    private let speechEnhancer: any SpeechEnhancing

    init(
        settingsStore _: DictationSettingsStore = DictationSettingsStore(),
        speechEnhancer: (any SpeechEnhancing)? = nil
    ) {
        self.speechEnhancer = speechEnhancer ?? SpeechAwareGainProcessor()
    }

    func processAudioFile(at sourceURL: URL, duration: TimeInterval?) async throws -> AudioPostProcessingResult {
        guard sourceURL.pathExtension.lowercased() == "wav" else {
            return .passthrough(url: sourceURL, duration: duration)
        }

        let samples: [Float]
        let fileSampleRate: Double
        do {
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

        do {
            let enhancement = try speechEnhancer.enhanceAudioFile(
                at: sourceURL,
                analysis: analysis
            )

            if enhancement.didRewriteAudio {
                AppLogger.info(
                    "Audio post-processing rewrote capture. outputURL=\(enhancement.outputURL.lastPathComponent)",
                    category: .dictation
                )
                return .rewritten(
                    sourceURL: sourceURL,
                    rewrittenURL: enhancement.outputURL,
                    duration: duration
                )
            }
        } catch {
            AppLogger.warning(
                "Skipping speech enhancement because the output could not be rewritten. error=\(error.localizedDescription)",
                category: .dictation
            )
        }

        return .passthrough(url: sourceURL, duration: duration)
    }
}
