@preconcurrency import AVFoundation
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
    private enum Configuration {
        static let vadFrameDurationSeconds = 0.02
        static let vadMode: WebRTCVADMode = .quality
        static let confirmationVADMode: WebRTCVADMode = .aggressive
        static let minimumSpeechFrameCount = 4
        static let minimumSpeechRunFrameCount = 3
        static let minimumConfirmationSpeechFrameCount = 2
        static let minimumConfirmationSpeechRunFrameCount = 2
        static let minimumSpeechRiseAboveNoiseFloorDB = 1.0
        static let absoluteSpeechFloorDBFS = -72.0
        static let speechPreRollFrameCount = 1
        static let speechHangoverFrameCount = 5
    }

    private struct Analysis {
        let shouldDiscardAsNoSpeech: Bool
        let speechFrameRatio: Double
        let confirmationSpeechFrameRatio: Double
        let longestSpeechDurationSeconds: Double
        let totalSpeechDurationSeconds: Double
        let rawSpeechFrameRatio: Double
        let noiseFloorDBFS: Double
        let speechLevelP75DBFS: Double

        var summaryLine: String {
            """
            wouldDiscard=\(shouldDiscardAsNoSpeech) \
            rawSpeechFrameRatio=\(String(format: "%.3f", rawSpeechFrameRatio)) \
            speechFrameRatio=\(String(format: "%.3f", speechFrameRatio)) \
            confirmationSpeechFrameRatio=\(String(format: "%.3f", confirmationSpeechFrameRatio)) \
            totalSpeechSeconds=\(String(format: "%.3f", totalSpeechDurationSeconds)) \
            longestSpeechSeconds=\(String(format: "%.3f", longestSpeechDurationSeconds)) \
            noiseFloorDBFS=\(String(format: "%.1f", noiseFloorDBFS)) \
            speechLevelP75DBFS=\(String(format: "%.1f", speechLevelP75DBFS))
            """
        }
    }

    private struct WAVEFile {
        let sampleRate: Double
        let samples: [Int16]

        var duration: TimeInterval {
            guard sampleRate > 0 else { return 0 }
            return Double(samples.count) / sampleRate
        }
    }

    private enum WAVEError: Error {
        case invalidHeader
        case missingFormatChunk
        case missingDataChunk
        case unsupportedFormat
        case invalidChunk
    }

    init(settingsStore _: DictationSettingsStore = DictationSettingsStore()) {}

    func processAudioFile(at sourceURL: URL, duration: TimeInterval?) async throws -> AudioPostProcessingResult {
        guard sourceURL.pathExtension.lowercased() == "wav" else {
            return .passthrough(url: sourceURL, duration: duration)
        }

        let waveFile: WAVEFile
        do {
            waveFile = try Self.readWAVEFile(at: sourceURL)
        } catch {
            AppLogger.warning(
                "Skipping audio post-processing because the wav file could not be parsed. error=\(error.localizedDescription)",
                category: .dictation
            )
            return .passthrough(url: sourceURL, duration: duration)
        }

        let effectiveDuration = duration ?? waveFile.duration
        let analysis = try Self.analyze(
            samples: waveFile.samples,
            sampleRate: waveFile.sampleRate
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
                "Local speech gate would have discarded this capture, but keeping it for transcription. \(analysis.summaryLine)",
                category: .dictation
            )
        }

        return .passthrough(url: sourceURL, duration: effectiveDuration)
    }

    private static func analyze(
        samples: [Int16],
        sampleRate: Double
    ) throws -> Analysis {
        guard !samples.isEmpty, sampleRate > 0 else {
            return Analysis(
                shouldDiscardAsNoSpeech: true,
                speechFrameRatio: 0,
                confirmationSpeechFrameRatio: 0,
                longestSpeechDurationSeconds: 0,
                totalSpeechDurationSeconds: 0,
                rawSpeechFrameRatio: 0,
                noiseFloorDBFS: -160,
                speechLevelP75DBFS: -160
            )
        }

        let sampleRateValue = Int(sampleRate.rounded())
        let frameSize = max(1, Int(sampleRate * Configuration.vadFrameDurationSeconds))
        let estimatedFrameCount = max(1, Int(ceil(Double(samples.count) / Double(frameSize))))
        let vad = try WebRTCVAD(
            sampleRate: sampleRateValue,
            mode: Configuration.vadMode
        )
        let confirmationVAD = try WebRTCVAD(
            sampleRate: sampleRateValue,
            mode: Configuration.confirmationVADMode
        )

        var rawSpeechFlags: [Bool] = []
        rawSpeechFlags.reserveCapacity(estimatedFrameCount)
        var rawConfirmationSpeechFlags: [Bool] = []
        rawConfirmationSpeechFlags.reserveCapacity(estimatedFrameCount)

        var frameStatsByIndex: [(sumSquares: Double, peakAmplitude: Double, sampleCount: Int)] = []
        frameStatsByIndex.reserveCapacity(estimatedFrameCount)

        for startIndex in stride(from: 0, to: samples.count, by: frameSize) {
            let endIndex = min(startIndex + frameSize, samples.count)
            let frame = samples[startIndex..<endIndex]
            frameStatsByIndex.append(frameStats(for: frame))
            let padded = paddedFrame(frame, targetLength: frameSize)
            rawSpeechFlags.append(try vad.process(frame: padded))
            rawConfirmationSpeechFlags.append(try confirmationVAD.process(frame: padded))
        }

        let speechFlags = smoothedSpeechFlags(from: rawSpeechFlags)
        let confirmationSpeechFlags = smoothedSpeechFlags(from: rawConfirmationSpeechFlags)
        let speechFrameCount = speechFlags.filter { $0 }.count
        let totalFrameCount = max(speechFlags.count, 1)
        let confirmationSpeechFrameCount = confirmationSpeechFlags.filter { $0 }.count
        let rawSpeechFrameCount = rawSpeechFlags.filter { $0 }.count
        let speechFrameRatio = Double(speechFrameCount) / Double(totalFrameCount)
        let confirmationSpeechFrameRatio = Double(confirmationSpeechFrameCount) / Double(totalFrameCount)
        let rawSpeechFrameRatio = Double(rawSpeechFrameCount) / Double(totalFrameCount)
        let longestSpeechRun = longestTrueRun(in: speechFlags)
        let confirmationLongestSpeechRun = longestTrueRun(in: confirmationSpeechFlags)
        let longestSpeechDurationSeconds = Double(longestSpeechRun * frameSize) / sampleRate
        let totalSpeechDurationSeconds = Double(speechFrameCount * frameSize) / sampleRate
        let allFrameFlags = Array(repeating: true, count: frameStatsByIndex.count)
        let nonSpeechFlags = speechFlags.map { !$0 }
        let noiseFloorDBFS = max(
            frameLevel(
                using: frameStatsByIndex,
                flags: nonSpeechFlags,
                fraction: 0.8
            ),
            frameLevel(
                using: frameStatsByIndex,
                flags: allFrameFlags,
                fraction: 0.2
            )
        )
        let speechLevelP75DBFS = frameLevel(
            using: frameStatsByIndex,
            flags: speechFlags,
            fraction: 0.75
        )
        let hasConfirmationSpeech =
            confirmationSpeechFrameCount >= Configuration.minimumConfirmationSpeechFrameCount &&
            confirmationLongestSpeechRun >= Configuration.minimumConfirmationSpeechRunFrameCount
        let hasSpeechRiseAboveNoiseFloor =
            speechLevelP75DBFS >= max(
                Configuration.absoluteSpeechFloorDBFS,
                noiseFloorDBFS + Configuration.minimumSpeechRiseAboveNoiseFloorDB
            )

        guard speechFrameCount >= Configuration.minimumSpeechFrameCount,
              longestSpeechRun >= Configuration.minimumSpeechRunFrameCount,
              hasSpeechRiseAboveNoiseFloor,
              hasConfirmationSpeech else {
            return Analysis(
                shouldDiscardAsNoSpeech: true,
                speechFrameRatio: speechFrameRatio,
                confirmationSpeechFrameRatio: confirmationSpeechFrameRatio,
                longestSpeechDurationSeconds: longestSpeechDurationSeconds,
                totalSpeechDurationSeconds: totalSpeechDurationSeconds,
                rawSpeechFrameRatio: rawSpeechFrameRatio,
                noiseFloorDBFS: noiseFloorDBFS,
                speechLevelP75DBFS: speechLevelP75DBFS
            )
        }

        return Analysis(
            shouldDiscardAsNoSpeech: false,
            speechFrameRatio: speechFrameRatio,
            confirmationSpeechFrameRatio: confirmationSpeechFrameRatio,
            longestSpeechDurationSeconds: longestSpeechDurationSeconds,
            totalSpeechDurationSeconds: totalSpeechDurationSeconds,
            rawSpeechFrameRatio: rawSpeechFrameRatio,
            noiseFloorDBFS: noiseFloorDBFS,
            speechLevelP75DBFS: speechLevelP75DBFS
        )
    }

    private static func frameStats(
        for frame: ArraySlice<Int16>
    ) -> (sumSquares: Double, peakAmplitude: Double, sampleCount: Int) {
        var sumSquares = 0.0
        var peakAmplitude = 0.0

        for sample in frame {
            let normalizedSample = normalizedAmplitude(for: sample)
            let amplitude = abs(normalizedSample)
            sumSquares += normalizedSample * normalizedSample
            peakAmplitude = max(peakAmplitude, amplitude)
        }

        return (sumSquares, peakAmplitude, frame.count)
    }

    private static func frameLevel(
        using frameStatsByIndex: [(sumSquares: Double, peakAmplitude: Double, sampleCount: Int)],
        flags: [Bool],
        fraction: Double
    ) -> Double {
        percentile(
            frameLevels(
                using: frameStatsByIndex,
                flags: flags
            ),
            fraction: fraction
        ) ?? -160
    }

    private static func frameLevels(
        using frameStatsByIndex: [(sumSquares: Double, peakAmplitude: Double, sampleCount: Int)],
        flags: [Bool]
    ) -> [Double] {
        flags.enumerated().compactMap { index, isIncluded -> Double? in
            guard isIncluded else { return nil }
            let stats = frameStatsByIndex[index]
            guard stats.sampleCount > 0 else { return nil }
            let rms = sqrt(stats.sumSquares / Double(stats.sampleCount))
            return decibels(for: rms)
        }
    }

    private static func smoothedSpeechFlags(from rawSpeechFlags: [Bool]) -> [Bool] {
        guard !rawSpeechFlags.isEmpty else { return [] }

        var smoothedFlags = Array(repeating: false, count: rawSpeechFlags.count)
        var index = 0

        while index < rawSpeechFlags.count {
            guard rawSpeechFlags[index] else {
                index += 1
                continue
            }

            var runEnd = index
            while runEnd < rawSpeechFlags.count, rawSpeechFlags[runEnd] {
                runEnd += 1
            }

            if runEnd - index >= Configuration.minimumSpeechRunFrameCount {
                let smoothedStart = max(0, index - Configuration.speechPreRollFrameCount)
                let smoothedEnd = min(
                    rawSpeechFlags.count,
                    runEnd + Configuration.speechHangoverFrameCount
                )
                for smoothedIndex in smoothedStart..<smoothedEnd {
                    smoothedFlags[smoothedIndex] = true
                }
            }

            index = runEnd
        }

        return smoothedFlags
    }

    private static func longestTrueRun(in flags: [Bool]) -> Int {
        var longestRun = 0
        var currentRun = 0

        for flag in flags {
            if flag {
                currentRun += 1
                longestRun = max(longestRun, currentRun)
            } else {
                currentRun = 0
            }
        }

        return longestRun
    }

    private static func paddedFrame(_ frame: ArraySlice<Int16>, targetLength: Int) -> ArraySlice<Int16> {
        guard frame.count < targetLength else { return frame }
        var paddedFrame = Array(frame)
        paddedFrame.append(contentsOf: repeatElement(0, count: targetLength - frame.count))
        return ArraySlice(paddedFrame)
    }

    private static func decibels(for normalizedAmplitude: Double) -> Double {
        guard normalizedAmplitude.isFinite, normalizedAmplitude > 0 else {
            return -160
        }

        return 20 * log10(normalizedAmplitude)
    }

    private static func normalizedAmplitude(for sample: Int16) -> Double {
        max(-1.0, min(Double(sample) / Double(Int16.max), 1.0))
    }

    private static func percentile(_ values: [Double], fraction: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        let sortedValues = values.sorted()
        let index = min(
            max(Int(Double(sortedValues.count - 1) * fraction), 0),
            sortedValues.count - 1
        )
        return sortedValues[index]
    }

    private static func readWAVEFile(at url: URL) throws -> WAVEFile {
        let data = try Data(contentsOf: url)
        guard data.count >= 44 else {
            throw WAVEError.invalidHeader
        }
        guard asciiString(in: data, offset: 0, count: 4) == "RIFF",
              asciiString(in: data, offset: 8, count: 4) == "WAVE" else {
            throw WAVEError.invalidHeader
        }

        var offset = 12
        var sampleRate: Double?
        var sampleCount: Int?
        var samples: [Int16]?

        while offset + 8 <= data.count {
            guard let chunkID = asciiString(in: data, offset: offset, count: 4),
                  let chunkSize = uint32LE(in: data, offset: offset + 4) else {
                throw WAVEError.invalidChunk
            }

            let chunkDataOffset = offset + 8
            let chunkDataEnd = chunkDataOffset + Int(chunkSize)
            guard chunkDataEnd <= data.count else {
                throw WAVEError.invalidChunk
            }

            switch chunkID {
            case "fmt ":
                guard chunkSize >= 16,
                      let audioFormat = uint16LE(in: data, offset: chunkDataOffset),
                      let channels = uint16LE(in: data, offset: chunkDataOffset + 2),
                      let parsedSampleRate = uint32LE(in: data, offset: chunkDataOffset + 4),
                      let blockAlign = uint16LE(in: data, offset: chunkDataOffset + 12),
                      let bitsPerSample = uint16LE(in: data, offset: chunkDataOffset + 14) else {
                    throw WAVEError.invalidChunk
                }

                guard audioFormat == 1,
                      channels == 1,
                      bitsPerSample == 16,
                      blockAlign == 2 else {
                    throw WAVEError.unsupportedFormat
                }

                sampleRate = Double(parsedSampleRate)

            case "data":
                guard chunkSize % 2 == 0 else {
                    throw WAVEError.invalidChunk
                }

                let parsedSampleCount = Int(chunkSize) / 2
                var parsedSamples: [Int16] = []
                parsedSamples.reserveCapacity(parsedSampleCount)

                var sampleOffset = chunkDataOffset
                for _ in 0..<parsedSampleCount {
                    guard let rawSample = uint16LE(in: data, offset: sampleOffset) else {
                        throw WAVEError.invalidChunk
                    }

                    parsedSamples.append(Int16(bitPattern: rawSample))
                    sampleOffset += 2
                }

                samples = parsedSamples
                sampleCount = parsedSampleCount

            default:
                break
            }

            offset = chunkDataEnd + Int(chunkSize % 2)
        }

        guard let sampleRate, sampleRate > 0 else {
            throw WAVEError.missingFormatChunk
        }
        guard let sampleCount, sampleCount > 0, let samples else {
            throw WAVEError.missingDataChunk
        }

        return WAVEFile(sampleRate: sampleRate, samples: samples)
    }

    private static func asciiString(in data: Data, offset: Int, count: Int) -> String? {
        guard offset >= 0, count >= 0, offset + count <= data.count else { return nil }
        return String(data: data[offset..<(offset + count)], encoding: .ascii)
    }

    private static func uint16LE(in data: Data, offset: Int) -> UInt16? {
        guard offset >= 0, offset + 2 <= data.count else { return nil }
        let lower = UInt16(data[data.startIndex + offset])
        let upper = UInt16(data[data.startIndex + offset + 1]) << 8
        return lower | upper
    }

    private static func uint32LE(in data: Data, offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= data.count else { return nil }
        let byte0 = UInt32(data[data.startIndex + offset])
        let byte1 = UInt32(data[data.startIndex + offset + 1]) << 8
        let byte2 = UInt32(data[data.startIndex + offset + 2]) << 16
        let byte3 = UInt32(data[data.startIndex + offset + 3]) << 24
        return byte0 | byte1 | byte2 | byte3
    }
}
