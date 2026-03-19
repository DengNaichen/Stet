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

    static func processed(outputURL: URL, sourceURL: URL, duration: TimeInterval?) -> Self {
        Self(
            url: outputURL,
            duration: duration,
            cleanupURLs: [sourceURL, outputURL],
            shouldDiscardAsNoSpeech: false
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
        static let minimumSpeechFrameCountAfterLeadingTransient = 10
        static let minimumSpeechRunFrameCountAfterLeadingTransient = 6
        static let minimumConfirmationSpeechFrameCountAfterLeadingTransient = 4
        static let minimumConfirmationSpeechRunFrameCountAfterLeadingTransient = 3
        static let minimumSpeechRiseAboveNoiseFloorDB = 1.0
        static let absoluteSpeechFloorDBFS = -72.0
        static let speechPreRollFrameCount = 1
        static let speechHangoverFrameCount = 5
        static let leadingTransientWindowSeconds = 0.35
        static let leadingTransientMaxDurationSeconds = 0.45
        static let promptTailGraceFrameCount = 12
        static let targetSpeechDBFS = -20.0
        static let peakCeilingDBFS = -1.0
        static let maximumGainDB = 12.0
        static let minimumGainToRewriteDB = 1.0
    }

    private struct Analysis {
        let shouldDiscardAsNoSpeech: Bool
        let recommendedGainDB: Double
        let speechFrameRatio: Double
        let confirmationSpeechFrameRatio: Double
        let longestSpeechDurationSeconds: Double
        let totalSpeechDurationSeconds: Double
        let rawSpeechFrameRatio: Double
        let noiseFloorDBFS: Double
        let speechLevelP75DBFS: Double
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

    private let settingsStore: DictationSettingsStore

    init(settingsStore: DictationSettingsStore = DictationSettingsStore()) {
        self.settingsStore = settingsStore
    }

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
        let settingsSnapshot = settingsStore.loadSnapshot()
        let analysis = try Self.analyze(
            samples: waveFile.samples,
            sampleRate: waveFile.sampleRate,
            interactionSoundsEnabled: settingsSnapshot.interactionSoundsEnabled
        )

        AppLogger.info(
            """
            Audio post-processing analyzed capture. \
            shouldDiscard=\(analysis.shouldDiscardAsNoSpeech), \
            rawSpeechFrameRatio=\(String(format: "%.3f", analysis.rawSpeechFrameRatio)), \
            speechFrameRatio=\(String(format: "%.3f", analysis.speechFrameRatio)), \
            confirmationSpeechFrameRatio=\(String(format: "%.3f", analysis.confirmationSpeechFrameRatio)), \
            totalSpeechSeconds=\(String(format: "%.3f", analysis.totalSpeechDurationSeconds)), \
            longestSpeechSeconds=\(String(format: "%.3f", analysis.longestSpeechDurationSeconds)), \
            noiseFloorDBFS=\(String(format: "%.1f", analysis.noiseFloorDBFS)), \
            speechLevelP75DBFS=\(String(format: "%.1f", analysis.speechLevelP75DBFS)), \
            gainDB=\(String(format: "%.1f", analysis.recommendedGainDB))
            """,
            category: .dictation
        )

        if analysis.shouldDiscardAsNoSpeech {
            return .discard(url: sourceURL, duration: effectiveDuration)
        }

        guard analysis.recommendedGainDB >= Configuration.minimumGainToRewriteDB else {
            return .passthrough(url: sourceURL, duration: effectiveDuration)
        }

        let outputURL = Self.makeProcessedFileURL(basedOn: sourceURL)
        do {
            try Self.writeNormalizedCopy(
                of: waveFile.samples,
                to: outputURL,
                sampleRate: waveFile.sampleRate,
                gainDB: analysis.recommendedGainDB
            )
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            AppLogger.warning(
                "Audio normalization failed; continuing with the original file. error=\(error.localizedDescription)",
                category: .dictation
            )
            return .passthrough(url: sourceURL, duration: effectiveDuration)
        }

        return .processed(outputURL: outputURL, sourceURL: sourceURL, duration: effectiveDuration)
    }

    private static func analyze(
        samples: [Int16],
        sampleRate: Double,
        interactionSoundsEnabled: Bool
    ) throws -> Analysis {
        guard !samples.isEmpty, sampleRate > 0 else {
            return Analysis(
                shouldDiscardAsNoSpeech: true,
                recommendedGainDB: 0,
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
        let speechEvidenceFlags = interactionSoundsEnabled
            ? suppressLeadingTransientSpeech(
                in: speechFlags,
                referenceFlags: rawSpeechFlags,
                maxStartFrameCount: Int(ceil(Configuration.leadingTransientWindowSeconds / Configuration.vadFrameDurationSeconds)),
                maxRunFrameCount: Int(ceil(Configuration.leadingTransientMaxDurationSeconds / Configuration.vadFrameDurationSeconds))
            )
            : speechFlags
        let confirmationSpeechEvidenceFlags = interactionSoundsEnabled
            ? suppressLeadingTransientSpeech(
                in: confirmationSpeechFlags,
                referenceFlags: rawConfirmationSpeechFlags,
                maxStartFrameCount: Int(ceil(Configuration.leadingTransientWindowSeconds / Configuration.vadFrameDurationSeconds)),
                maxRunFrameCount: Int(ceil(Configuration.leadingTransientMaxDurationSeconds / Configuration.vadFrameDurationSeconds))
            )
            : confirmationSpeechFlags
        let didSuppressLeadingTransient = speechEvidenceFlags != speechFlags ||
            confirmationSpeechEvidenceFlags != confirmationSpeechFlags
        let minimumSpeechFrameCount = didSuppressLeadingTransient
            ? Configuration.minimumSpeechFrameCountAfterLeadingTransient
            : Configuration.minimumSpeechFrameCount
        let minimumSpeechRunFrameCount = didSuppressLeadingTransient
            ? Configuration.minimumSpeechRunFrameCountAfterLeadingTransient
            : Configuration.minimumSpeechRunFrameCount
        let minimumConfirmationSpeechFrameCount = didSuppressLeadingTransient
            ? Configuration.minimumConfirmationSpeechFrameCountAfterLeadingTransient
            : Configuration.minimumConfirmationSpeechFrameCount
        let minimumConfirmationSpeechRunFrameCount = didSuppressLeadingTransient
            ? Configuration.minimumConfirmationSpeechRunFrameCountAfterLeadingTransient
            : Configuration.minimumConfirmationSpeechRunFrameCount
        let speechFrameCount = speechEvidenceFlags.filter { $0 }.count
        let totalFrameCount = max(speechEvidenceFlags.count, 1)
        let confirmationSpeechFrameCount = confirmationSpeechEvidenceFlags.filter { $0 }.count
        let rawSpeechFrameCount = rawSpeechFlags.filter { $0 }.count
        let speechFrameRatio = Double(speechFrameCount) / Double(totalFrameCount)
        let confirmationSpeechFrameRatio = Double(confirmationSpeechFrameCount) / Double(totalFrameCount)
        let rawSpeechFrameRatio = Double(rawSpeechFrameCount) / Double(totalFrameCount)
        let longestSpeechRun = longestTrueRun(in: speechEvidenceFlags)
        let confirmationLongestSpeechRun = longestTrueRun(in: confirmationSpeechEvidenceFlags)
        let longestSpeechDurationSeconds = Double(longestSpeechRun * frameSize) / sampleRate
        let totalSpeechDurationSeconds = Double(speechFrameCount * frameSize) / sampleRate
        let allFrameFlags = Array(repeating: true, count: frameStatsByIndex.count)
        let nonSpeechFlags = speechEvidenceFlags.map { !$0 }
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
            flags: speechEvidenceFlags,
            fraction: 0.75
        )
        let promptOnlyLikely = interactionSoundsEnabled &&
            isLikelyPromptOnlyCapture(
                rawSpeechFlags: rawSpeechFlags,
                rawConfirmationSpeechFlags: rawConfirmationSpeechFlags,
                maxStartFrameCount: Int(ceil(Configuration.leadingTransientWindowSeconds / Configuration.vadFrameDurationSeconds)),
                maxRunFrameCount: Int(ceil(Configuration.leadingTransientMaxDurationSeconds / Configuration.vadFrameDurationSeconds)),
                promptTailGraceFrameCount: Configuration.promptTailGraceFrameCount,
                minimumConfirmationSpeechRunFrameCount: minimumConfirmationSpeechRunFrameCount
            )
        let hasConfirmationSpeech =
            confirmationSpeechFrameCount >= minimumConfirmationSpeechFrameCount &&
            confirmationLongestSpeechRun >= minimumConfirmationSpeechRunFrameCount
        let hasSpeechRiseAboveNoiseFloor =
            speechLevelP75DBFS >= max(
                Configuration.absoluteSpeechFloorDBFS,
                noiseFloorDBFS + Configuration.minimumSpeechRiseAboveNoiseFloorDB
            )

        guard !promptOnlyLikely,
              speechFrameCount >= minimumSpeechFrameCount,
              longestSpeechRun >= minimumSpeechRunFrameCount,
              hasSpeechRiseAboveNoiseFloor,
              hasConfirmationSpeech else {
            return Analysis(
                shouldDiscardAsNoSpeech: true,
                recommendedGainDB: 0,
                speechFrameRatio: speechFrameRatio,
                confirmationSpeechFrameRatio: confirmationSpeechFrameRatio,
                longestSpeechDurationSeconds: longestSpeechDurationSeconds,
                totalSpeechDurationSeconds: totalSpeechDurationSeconds,
                rawSpeechFrameRatio: rawSpeechFrameRatio,
                noiseFloorDBFS: noiseFloorDBFS,
                speechLevelP75DBFS: speechLevelP75DBFS
            )
        }

        var speechSquareSum = 0.0
        var speechPeakAmplitude = 0.0
        var speechSampleCount = 0

        for (index, isSpeech) in speechEvidenceFlags.enumerated() where isSpeech {
            let stats = frameStatsByIndex[index]
            speechSquareSum += stats.sumSquares
            speechPeakAmplitude = max(speechPeakAmplitude, stats.peakAmplitude)
            speechSampleCount += stats.sampleCount
        }

        guard speechSampleCount > 0 else {
            return Analysis(
                shouldDiscardAsNoSpeech: true,
                recommendedGainDB: 0,
                speechFrameRatio: speechFrameRatio,
                confirmationSpeechFrameRatio: confirmationSpeechFrameRatio,
                longestSpeechDurationSeconds: longestSpeechDurationSeconds,
                totalSpeechDurationSeconds: totalSpeechDurationSeconds,
                rawSpeechFrameRatio: rawSpeechFrameRatio,
                noiseFloorDBFS: noiseFloorDBFS,
                speechLevelP75DBFS: speechLevelP75DBFS
            )
        }

        let speechRMS = sqrt(speechSquareSum / Double(speechSampleCount))
        let speechDBFS = decibels(for: speechRMS)
        let peakDBFS = decibels(for: speechPeakAmplitude)

        let targetGainDB = min(
            max(Configuration.targetSpeechDBFS - speechDBFS, 0),
            Configuration.maximumGainDB
        )
        let headroomGainDB = max(Configuration.peakCeilingDBFS - peakDBFS, 0)
        let recommendedGainDB = min(targetGainDB, headroomGainDB)

        return Analysis(
            shouldDiscardAsNoSpeech: false,
            recommendedGainDB: recommendedGainDB,
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

    private static func suppressLeadingTransientSpeech(
        in flags: [Bool],
        referenceFlags: [Bool],
        maxStartFrameCount: Int,
        maxRunFrameCount: Int
    ) -> [Bool] {
        guard maxStartFrameCount > 0, maxRunFrameCount > 0, !flags.isEmpty else {
            return flags
        }

        guard let leadingRun = leadingSpeechRun(
            in: referenceFlags,
            maxStartFrameCount: maxStartFrameCount,
            maxRunFrameCount: maxRunFrameCount
        ) else {
            return flags
        }

        var suppressedFlags = flags
        let suppressedEnd = min(
            suppressedFlags.count,
            leadingRun.upperBound + Configuration.speechHangoverFrameCount
        )
        for index in leadingRun.lowerBound..<suppressedEnd {
            suppressedFlags[index] = false
        }

        return suppressedFlags
    }

    private static func isLikelyPromptOnlyCapture(
        rawSpeechFlags: [Bool],
        rawConfirmationSpeechFlags: [Bool],
        maxStartFrameCount: Int,
        maxRunFrameCount: Int,
        promptTailGraceFrameCount: Int,
        minimumConfirmationSpeechRunFrameCount: Int
    ) -> Bool {
        guard let leadingRun = leadingSpeechRun(
            in: rawSpeechFlags,
            maxStartFrameCount: maxStartFrameCount,
            maxRunFrameCount: maxRunFrameCount
        ) else {
            return false
        }

        let postPromptStartIndex = min(
            rawConfirmationSpeechFlags.count,
            leadingRun.upperBound + promptTailGraceFrameCount
        )
        return !containsTrueRun(
            in: rawConfirmationSpeechFlags,
            startingAt: postPromptStartIndex,
            minimumRunLength: minimumConfirmationSpeechRunFrameCount
        )
    }

    private static func leadingSpeechRun(
        in flags: [Bool],
        maxStartFrameCount: Int,
        maxRunFrameCount: Int
    ) -> Range<Int>? {
        guard maxStartFrameCount > 0,
              maxRunFrameCount > 0,
              let firstSpeechIndex = flags.firstIndex(of: true),
              firstSpeechIndex < min(maxStartFrameCount, flags.count) else {
            return nil
        }

        var runEnd = firstSpeechIndex
        while runEnd < flags.count, flags[runEnd] {
            runEnd += 1
        }

        guard runEnd - firstSpeechIndex <= maxRunFrameCount else {
            return nil
        }

        return firstSpeechIndex..<runEnd
    }

    private static func containsTrueRun(
        in flags: [Bool],
        startingAt startIndex: Int,
        minimumRunLength: Int
    ) -> Bool {
        guard minimumRunLength > 0, startIndex < flags.count else { return false }

        var currentRunLength = 0
        for index in startIndex..<flags.count {
            if flags[index] {
                currentRunLength += 1
                if currentRunLength >= minimumRunLength {
                    return true
                }
            } else {
                currentRunLength = 0
            }
        }

        return false
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

                sampleCount = parsedSampleCount
                samples = parsedSamples

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

    private static func writeNormalizedCopy(
        of samples: [Int16],
        to outputURL: URL,
        sampleRate: Double,
        gainDB: Double
    ) throws {
        guard sampleRate.isFinite,
              sampleRate > 0,
              let sampleRateValue = UInt32(exactly: Int(sampleRate.rounded())) else {
            throw WAVEError.unsupportedFormat
        }

        let gainMultiplier = pow(10, gainDB / 20)
        let pcmBytes = samples.reduce(into: Data()) { data, sample in
            let amplifiedSample = normalizedAmplitude(for: sample) * gainMultiplier
            let clampedSample = max(-1.0, min(amplifiedSample, 1.0))
            let pcmSample = Int16(clampedSample * Double(Int16.max))
            data.append(contentsOf: withUnsafeBytes(of: pcmSample.littleEndian, Array.init))
        }

        let fmtChunkSize = UInt32(16)
        let dataChunkSize = UInt32(pcmBytes.count)
        let riffChunkSize = UInt32(4 + (8 + fmtChunkSize) + (8 + dataChunkSize))
        let byteRate = sampleRateValue * 2
        let blockAlign = UInt16(2)
        let bitsPerSample = UInt16(16)

        var waveData = Data()
        waveData.append(contentsOf: Array("RIFF".utf8))
        appendLittleEndian(riffChunkSize, to: &waveData)
        waveData.append(contentsOf: Array("WAVE".utf8))
        waveData.append(contentsOf: Array("fmt ".utf8))
        appendLittleEndian(fmtChunkSize, to: &waveData)
        appendLittleEndian(UInt16(1), to: &waveData)
        appendLittleEndian(UInt16(1), to: &waveData)
        appendLittleEndian(sampleRateValue, to: &waveData)
        appendLittleEndian(byteRate, to: &waveData)
        appendLittleEndian(blockAlign, to: &waveData)
        appendLittleEndian(bitsPerSample, to: &waveData)
        waveData.append(contentsOf: Array("data".utf8))
        appendLittleEndian(dataChunkSize, to: &waveData)
        waveData.append(pcmBytes)

        try waveData.write(to: outputURL, options: .atomic)
    }

    private static func makeProcessedFileURL(basedOn sourceURL: URL) -> URL {
        sourceURL.deletingLastPathComponent().appendingPathComponent(
            "\(sourceURL.deletingPathExtension().lastPathComponent)-normalized-\(UUID().uuidString).wav"
        )
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

    private static func appendLittleEndian<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var littleEndianValue = value.littleEndian
        withUnsafeBytes(of: &littleEndianValue) { data.append(contentsOf: $0) }
    }
}

private extension InteractionSoundPreset {
    var startSoundFileName: String {
        switch self {
        case .soft:
            return "Submarine"
        case .glass:
            return "Glass"
        }
    }
}
