@preconcurrency import AVFoundation
import FluidAudio
import Foundation
import os

final class DefaultAudioPostProcessor: AudioPostProcessing, @unchecked Sendable {
    private let speechEnhancer: any SpeechEnhancing
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.openwhispr.Stet", category: "AudioProcessing")

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
            logger.warning(
                "Skipping audio post-processing because the audio file could not be loaded. error=\(error.localizedDescription)"
            )
            return .passthrough(url: sourceURL, duration: duration)
        }

        let analysisResult = try await AudioSignalAnalyzer.analyzeForPostProcessing(
            samples: samples,
            sampleRate: fileSampleRate
        )
        let analysis = analysisResult.analysis
        let vadSegmentation = analysisResult.segmentation

        logger.info(
            "Audio post-processing analyzed capture. \(analysis.summaryLine)"
        )
        if UserDefaults.standard.bool(forKey: MacPreferences.dictationPerfTracingEnabled) {
            logger.warning(
                "Audio post-processing summary. \(analysis.summaryLine)"
            )
        }

        if analysis.shouldDiscardAsNoSpeech {
            logger.warning(
                "Discarding capture as no speech was detected. \(analysis.summaryLine)"
            )
            return .discard(url: sourceURL, duration: duration)
        }

        var currentURL = sourceURL
        var cleanupURLs: [URL] = [sourceURL]
        var currentDuration = duration

        do {
            let enhancement = try speechEnhancer.enhanceAudioFile(
                at: sourceURL,
                analysis: analysis
            )

            if enhancement.didRewriteAudio {
                currentURL = enhancement.outputURL
                cleanupURLs.append(enhancement.outputURL)
                logger.info(
                    "Audio post-processing rewrote capture. outputURL=\(enhancement.outputURL.lastPathComponent)"
                )
            }
        } catch {
            logger.warning(
                "Skipping speech enhancement because the output could not be rewritten. error=\(error.localizedDescription)"
            )
        }

        do {
            let trimmingSamples: [Float]
            let trimmingSampleRate: Double
            if currentURL == sourceURL {
                trimmingSamples = vadSegmentation.samples
                trimmingSampleRate = vadSegmentation.sampleRate
            } else {
                let rewrittenAudioFile = try AVAudioFile(forReading: currentURL)
                trimmingSampleRate = rewrittenAudioFile.fileFormat.sampleRate
                trimmingSamples = try AudioConverter().resampleAudioFile(currentURL)
            }

            let trimResult = VadSilenceTrimmer.trim(
                samples: trimmingSamples,
                sampleRate: trimmingSampleRate,
                segments: vadSegmentation.segments
            )

            if trimResult.didTrim {
                #if os(macOS)
                    let trimmedURL = try AudioWavWriter.writePCM16MonoWav(
                        samples: trimResult.samples,
                        filePrefix: "speech-trimmed"
                    )
                    currentURL = trimmedURL
                    cleanupURLs.append(trimmedURL)
                #else
                    do {
                        let trimmedURL = try AudioM4AWriter.writeAACM4A(
                            samples: trimResult.samples,
                            sampleRate: trimmingSampleRate,
                            filePrefix: "speech-trimmed"
                        )
                        currentURL = trimmedURL
                        cleanupURLs.append(trimmedURL)
                    } catch {
                        logger.warning(
                            "Falling back to wav because trimmed m4a output could not be written. error=\(error.localizedDescription)"
                        )
                        let trimmedURL = try AudioWavWriter.writePCM16MonoWav(
                            samples: trimResult.samples,
                            filePrefix: "speech-trimmed"
                        )
                        currentURL = trimmedURL
                        cleanupURLs.append(trimmedURL)
                    }
                #endif
                currentDuration = trimResult.duration
                logger.info(
                    "Audio post-processing trimmed silence. removedSeconds=\(String(format: "%.2f", trimResult.removedSeconds))"
                )
            }
        } catch {
            logger.warning(
                "Skipping silence trimming because the output could not be rewritten. error=\(error.localizedDescription)"
            )
        }

        if currentURL == sourceURL, cleanupURLs.count == 1 {
            return .passthrough(url: sourceURL, duration: currentDuration)
        }

        return AudioPostProcessingResult(
            url: currentURL,
            duration: currentDuration,
            cleanupURLs: cleanupURLs,
            shouldDiscardAsNoSpeech: false
        )
    }
}
