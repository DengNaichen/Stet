import FluidAudio
import Foundation

enum VadSilenceTrimmer {
    struct Result: Sendable {
        let samples: [Float]
        let duration: TimeInterval
        let removedSeconds: TimeInterval
        let didTrim: Bool
    }

    struct Configuration: Sendable {
        let minimumSegmentSeconds: TimeInterval
        let energyFrameSeconds: TimeInterval
        let energyHopSeconds: TimeInterval
        let energyMarginDB: Double
        let maxMergeGapSeconds: TimeInterval
        let padBeforeSeconds: TimeInterval
        let padAfterSeconds: TimeInterval
        let interSegmentSilenceSeconds: TimeInterval
        let minimumRemovedSeconds: TimeInterval

        static let `default` = Configuration(
            minimumSegmentSeconds: 0.2,
            energyFrameSeconds: 0.02,
            energyHopSeconds: 0.01,
            energyMarginDB: 10,
            maxMergeGapSeconds: 0.25,
            padBeforeSeconds: 0.15,
            padAfterSeconds: 0.15,
            interSegmentSilenceSeconds: 0.12,
            minimumRemovedSeconds: 0.35
        )
    }

    static func trim(
        samples: [Float],
        sampleRate: Double,
        segments: [VadSegment],
        config: Configuration = .default
    ) -> Result {
        guard !samples.isEmpty, sampleRate > 0 else {
            return Result(samples: samples, duration: 0, removedSeconds: 0, didTrim: false)
        }

        let roundedRate = max(1, Int(sampleRate.rounded()))
        let maxMergeGapSamples = Int((config.maxMergeGapSeconds * sampleRate).rounded())
        let padBeforeSamples = Int((config.padBeforeSeconds * sampleRate).rounded())
        let padAfterSamples = Int((config.padAfterSeconds * sampleRate).rounded())
        let interSegmentSilenceSamples = max(0, Int((config.interSegmentSilenceSeconds * sampleRate).rounded()))
        let minimumRemovedSamples = max(0, Int((config.minimumRemovedSeconds * sampleRate).rounded()))

        var intervals: [(start: Int, end: Int)] = []
        intervals.reserveCapacity(max(segments.count, 4))

        for segment in segments {
            guard (segment.endTime - segment.startTime) >= config.minimumSegmentSeconds else { continue }
            let lower = max(0, min(segment.startSample(sampleRate: roundedRate), samples.count))
            let upper = max(lower, min(segment.endSample(sampleRate: roundedRate), samples.count))
            guard upper > lower else { continue }
            intervals.append((lower, upper))
        }

        intervals.append(
            contentsOf: energyActiveIntervals(
                samples: samples,
                sampleRate: sampleRate,
                minDurationSeconds: config.minimumSegmentSeconds,
                frameSeconds: config.energyFrameSeconds,
                hopSeconds: config.energyHopSeconds,
                marginDB: config.energyMarginDB
            ))
        intervals.sort { $0.start < $1.start }

        guard !intervals.isEmpty else {
            let duration = TimeInterval(samples.count) / sampleRate
            return Result(samples: samples, duration: duration, removedSeconds: 0, didTrim: false)
        }

        intervals = mergeIntervals(intervals, maxGapSamples: maxMergeGapSamples)
        intervals = intervals.map { interval in
            let start = max(0, interval.start - padBeforeSamples)
            let end = min(samples.count, interval.end + padAfterSamples)
            return (start, max(start, end))
        }.filter { $0.end > $0.start }
        intervals = mergeIntervals(intervals, maxGapSamples: 0)

        let keptSampleCount = intervals.reduce(0) { $0 + ($1.end - $1.start) }
        let gapSamples = max(0, intervals.count - 1) * interSegmentSilenceSamples
        let outputCount = keptSampleCount + gapSamples
        let removedSamples = max(0, samples.count - outputCount)
        guard removedSamples >= minimumRemovedSamples else {
            let duration = TimeInterval(samples.count) / sampleRate
            return Result(samples: samples, duration: duration, removedSeconds: 0, didTrim: false)
        }

        var output: [Float] = []
        output.reserveCapacity(outputCount)

        for (index, interval) in intervals.enumerated() {
            if index > 0, interSegmentSilenceSamples > 0 {
                output.append(contentsOf: repeatElement(Float(0), count: interSegmentSilenceSamples))
            }
            output.append(contentsOf: samples[interval.start..<interval.end])
        }

        let duration = TimeInterval(output.count) / sampleRate
        let removedSeconds = TimeInterval(removedSamples) / sampleRate
        return Result(samples: output, duration: duration, removedSeconds: removedSeconds, didTrim: true)
    }

    private static func mergeIntervals(
        _ intervals: [(start: Int, end: Int)],
        maxGapSamples: Int
    ) -> [(start: Int, end: Int)] {
        guard intervals.count > 1 else { return intervals }

        var merged: [(start: Int, end: Int)] = []
        merged.reserveCapacity(intervals.count)

        var current = intervals[0]
        for interval in intervals.dropFirst() {
            if interval.start <= current.end + maxGapSamples {
                current.end = max(current.end, interval.end)
            } else {
                merged.append(current)
                current = interval
            }
        }
        merged.append(current)

        return merged
    }

    private static func energyActiveIntervals(
        samples: [Float],
        sampleRate: Double,
        minDurationSeconds: TimeInterval,
        frameSeconds: TimeInterval,
        hopSeconds: TimeInterval,
        marginDB: Double
    ) -> [(start: Int, end: Int)] {
        guard !samples.isEmpty, sampleRate > 0 else { return [] }

        let frameLength = max(1, Int((sampleRate * frameSeconds).rounded()))
        let hopLength = max(1, Int((sampleRate * hopSeconds).rounded()))
        guard frameLength <= samples.count else { return [] }

        var prefixSquares = Array(repeating: 0.0, count: samples.count + 1)
        prefixSquares[0] = 0
        for index in samples.indices {
            let value = Double(samples[index])
            prefixSquares[index + 1] = prefixSquares[index] + value * value
        }

        var frameDBs: [Double] = []
        frameDBs.reserveCapacity(max(1, (samples.count - frameLength) / hopLength))

        var frameStart = 0
        while frameStart + frameLength <= samples.count {
            let frameEnd = frameStart + frameLength
            let sumSquares = prefixSquares[frameEnd] - prefixSquares[frameStart]
            let meanSquare = sumSquares / Double(frameLength)
            let db = meanSquare > 0 ? 10 * log10(meanSquare) : -160
            frameDBs.append(db)
            frameStart += hopLength
        }

        guard let noiseFloorDB = percentile(frameDBs, 0.2) else { return [] }
        let thresholdDB = noiseFloorDB + marginDB

        let minimumSamples = max(1, Int((minDurationSeconds * sampleRate).rounded()))
        var intervals: [(start: Int, end: Int)] = []
        var currentStart: Int? = nil
        var index = 0
        frameStart = 0

        while frameStart + frameLength <= samples.count, index < frameDBs.count {
            let isActive = frameDBs[index] >= thresholdDB
            if isActive {
                if currentStart == nil {
                    currentStart = frameStart
                }
            } else if let start = currentStart {
                let end = min(samples.count, frameStart + frameLength)
                if end - start >= minimumSamples {
                    intervals.append((start, end))
                }
                currentStart = nil
            }

            frameStart += hopLength
            index += 1
        }

        if let start = currentStart {
            let end = samples.count
            if end - start >= minimumSamples {
                intervals.append((start, end))
            }
        }

        return intervals
    }

    private static func percentile(_ values: [Double], _ percentile: Double) -> Double? {
        guard !values.isEmpty else { return nil }

        let sorted = values.sorted()
        let clamped = min(max(percentile, 0), 1)
        let position = clamped * Double(sorted.count - 1)
        let lowerIndex = Int(floor(position))
        let upperIndex = Int(ceil(position))
        if lowerIndex == upperIndex {
            return sorted[lowerIndex]
        }

        let lowerWeight = Double(upperIndex) - position
        let upperWeight = position - Double(lowerIndex)
        return sorted[lowerIndex] * lowerWeight + sorted[upperIndex] * upperWeight
    }
}
