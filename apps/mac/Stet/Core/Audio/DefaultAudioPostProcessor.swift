import Foundation

protocol AudioPostProcessing: Sendable {
    nonisolated func processAudioFile(at sourceURL: URL, duration: TimeInterval?) throws -> AudioPostProcessingResult
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
        static let analysisWindowDurationSeconds = 0.02
        static let minimumSpeechFrameRatio = 0.06
        static let minimumContiguousSpeechDurationSeconds = 0.18
        static let absoluteSpeechThresholdDBFS = -52.0
        static let relativeSpeechThresholdDB = 10.0
        static let targetSpeechDBFS = -20.0
        static let peakCeilingDBFS = -1.0
        static let maximumGainDB = 12.0
        static let minimumGainToRewriteDB = 1.0
    }

    private struct Analysis {
        let shouldDiscardAsNoSpeech: Bool
        let recommendedGainDB: Double
        let speechFrameRatio: Double
        let longestSpeechDurationSeconds: Double
        let noiseFloorDBFS: Double
        let speechThresholdDBFS: Double
    }

    private struct WAVEFile {
        let sampleRate: Double
        let samples: [Float]

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

    nonisolated func processAudioFile(at sourceURL: URL, duration: TimeInterval?) throws -> AudioPostProcessingResult {
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
        let analysis = Self.analyze(samples: waveFile.samples, sampleRate: waveFile.sampleRate)

        AppLogger.info(
            """
            Audio post-processing analyzed capture. \
            shouldDiscard=\(analysis.shouldDiscardAsNoSpeech), \
            speechFrameRatio=\(String(format: "%.3f", analysis.speechFrameRatio)), \
            longestSpeechSeconds=\(String(format: "%.3f", analysis.longestSpeechDurationSeconds)), \
            noiseFloorDBFS=\(String(format: "%.1f", analysis.noiseFloorDBFS)), \
            speechThresholdDBFS=\(String(format: "%.1f", analysis.speechThresholdDBFS)), \
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

    private static func analyze(samples: [Float], sampleRate: Double) -> Analysis {
        guard !samples.isEmpty, sampleRate > 0 else {
            return Analysis(
                shouldDiscardAsNoSpeech: true,
                recommendedGainDB: 0,
                speechFrameRatio: 0,
                longestSpeechDurationSeconds: 0,
                noiseFloorDBFS: -160,
                speechThresholdDBFS: Configuration.absoluteSpeechThresholdDBFS
            )
        }

        let frameSize = max(1, Int(sampleRate * Configuration.analysisWindowDurationSeconds))
        var frameDBs: [Double] = []
        frameDBs.reserveCapacity(max(1, samples.count / frameSize))

        var peakAmplitude = 0.0
        var maxFrameDBFS = -160.0

        for startIndex in stride(from: 0, to: samples.count, by: frameSize) {
            let endIndex = min(startIndex + frameSize, samples.count)
            let frame = samples[startIndex..<endIndex]
            let stats = frameStats(for: frame)
            frameDBs.append(stats.rmsDBFS)
            peakAmplitude = max(peakAmplitude, stats.peakAmplitude)
            maxFrameDBFS = max(maxFrameDBFS, stats.rmsDBFS)
        }

        let noiseFloorDBFS = percentile(frameDBs, fraction: 0.2) ?? -160
        let speechThresholdDBFS = max(
            Configuration.absoluteSpeechThresholdDBFS,
            noiseFloorDBFS + Configuration.relativeSpeechThresholdDB
        )

        var speechFrameCount = 0
        var currentSpeechRun = 0
        var longestSpeechRun = 0
        var speechSquareSum = 0.0
        var speechSampleCount = 0

        for startIndex in stride(from: 0, to: samples.count, by: frameSize) {
            let endIndex = min(startIndex + frameSize, samples.count)
            let frame = samples[startIndex..<endIndex]
            let stats = frameStats(for: frame)
            let isSpeech = stats.rmsDBFS >= speechThresholdDBFS

            if isSpeech {
                speechFrameCount += 1
                currentSpeechRun += 1
                longestSpeechRun = max(longestSpeechRun, currentSpeechRun)
                speechSquareSum += stats.sumSquares
                speechSampleCount += frame.count
            } else {
                currentSpeechRun = 0
            }
        }

        let totalFrameCount = max(frameDBs.count, 1)
        let speechFrameRatio = Double(speechFrameCount) / Double(totalFrameCount)
        let longestSpeechDurationSeconds = Double(longestSpeechRun * frameSize) / sampleRate

        let shouldDiscardAsNoSpeech = maxFrameDBFS < Configuration.absoluteSpeechThresholdDBFS ||
            (speechFrameRatio < Configuration.minimumSpeechFrameRatio &&
             longestSpeechDurationSeconds < Configuration.minimumContiguousSpeechDurationSeconds)

        guard !shouldDiscardAsNoSpeech,
              speechSampleCount > 0 else {
            return Analysis(
                shouldDiscardAsNoSpeech: true,
                recommendedGainDB: 0,
                speechFrameRatio: speechFrameRatio,
                longestSpeechDurationSeconds: longestSpeechDurationSeconds,
                noiseFloorDBFS: noiseFloorDBFS,
                speechThresholdDBFS: speechThresholdDBFS
            )
        }

        let speechRMS = sqrt(speechSquareSum / Double(speechSampleCount))
        let speechDBFS = decibels(for: speechRMS)
        let peakDBFS = decibels(for: peakAmplitude)

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
            longestSpeechDurationSeconds: longestSpeechDurationSeconds,
            noiseFloorDBFS: noiseFloorDBFS,
            speechThresholdDBFS: speechThresholdDBFS
        )
    }

    private static func frameStats(for frame: ArraySlice<Float>) -> (rmsDBFS: Double, peakAmplitude: Double, sumSquares: Double) {
        var sumSquares = 0.0
        var peakAmplitude = 0.0

        for sample in frame {
            let normalizedSample = Double(sample)
            let amplitude = abs(normalizedSample)
            sumSquares += normalizedSample * normalizedSample
            peakAmplitude = max(peakAmplitude, amplitude)
        }

        let rms = sqrt(sumSquares / Double(max(frame.count, 1)))
        return (decibels(for: rms), peakAmplitude, sumSquares)
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

    private static func decibels(for normalizedAmplitude: Double) -> Double {
        guard normalizedAmplitude.isFinite, normalizedAmplitude > 0 else {
            return -160
        }

        return 20 * log10(normalizedAmplitude)
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
        var samples: [Float]?

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
                var parsedSamples: [Float] = []
                parsedSamples.reserveCapacity(parsedSampleCount)

                var sampleOffset = chunkDataOffset
                for _ in 0..<parsedSampleCount {
                    guard let rawSample = uint16LE(in: data, offset: sampleOffset) else {
                        throw WAVEError.invalidChunk
                    }

                    let signedSample = Int16(bitPattern: rawSample)
                    let normalizedSample = max(
                        -1.0,
                        min(Double(signedSample) / Double(Int16.max), 1.0)
                    )
                    parsedSamples.append(Float(normalizedSample))
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
        of samples: [Float],
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
            let amplifiedSample = Double(sample) * gainMultiplier
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
