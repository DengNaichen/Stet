import Foundation

final class StreamingSpeechCaptureFrontend: @unchecked Sendable {
    typealias SpeechDecisionProvider = @Sendable (ArraySlice<Int16>) throws -> Bool

    struct Diagnostics: Sendable {
        let analyzedFrameCountSinceActivation: Int
        let rawPrimarySpeechFrameCount: Int
        let rawConfirmationSpeechFrameCount: Int
        let acceptedPrimarySpeechFrameCount: Int
        let acceptedConfirmationSpeechFrameCount: Int
        let transientNoiseFrameCount: Int
        let zeroCrossingNoiseFrameCount: Int
        let lowZeroCrossingNoiseFrameCount: Int
        let noiseFloorDBFS: Double
        let commitStartedFrameIndex: Int?
        let commitStartRawRMSDBFS: Double?
        let commitStartRawPeakDBFS: Double?
        let commitStartZeroCrossingRate: Double?
        let commitStartSpeechThresholdDBFS: Double?
        let committedFrameCount: Int
        let endpointDetected: Bool

        var summaryLine: String {
            func format(_ value: Double?) -> String {
                guard let value, value.isFinite else { return "na" }
                return String(format: "%.1f", value)
            }

            func formatRatio(_ value: Double?) -> String {
                guard let value, value.isFinite else { return "na" }
                return String(format: "%.3f", value)
            }

            return """
            actFrames=\(analyzedFrameCountSinceActivation) rawP=\(rawPrimarySpeechFrameCount) rawC=\(rawConfirmationSpeechFrameCount) \
            accP=\(acceptedPrimarySpeechFrameCount) accC=\(acceptedConfirmationSpeechFrameCount) \
            tr=\(transientNoiseFrameCount) zc=\(zeroCrossingNoiseFrameCount) lzc=\(lowZeroCrossingNoiseFrameCount) \
            nf=\(format(noiseFloorDBFS)) commitAt=\(commitStartedFrameIndex.map(String.init) ?? "na") \
            rms=\(format(commitStartRawRMSDBFS)) peak=\(format(commitStartRawPeakDBFS)) \
            zcr=\(formatRatio(commitStartZeroCrossingRate)) thr=\(format(commitStartSpeechThresholdDBFS)) \
            committed=\(committedFrameCount) endpoint=\(endpointDetected)
            """
        }
    }

    struct Configuration: Sendable {
        let sampleRate: Double
        let frameDurationSeconds: Double
        let ringBufferDurationSeconds: Double
        let minimumNoiseCalibrationFrameCount: Int
        let speechStartWindowFrameCount: Int
        let primarySpeechStartThreshold: Int
        let confirmationSpeechStartThreshold: Int
        let minimumLearnableNoiseFloorDBFS: Double
        let minimumSpeechRiseAboveNoiseFloorDB: Double
        let absoluteSpeechFloorDBFS: Double
        let minimumCommittedSpeechDurationSeconds: Double
        let endpointTrailingSilenceDurationSeconds: Double
        let primaryVADMode: WebRTCVADMode
        let confirmationVADMode: WebRTCVADMode
        let streamingGainTargetDBFS: Double
        let peakCeilingDBFS: Double
        let maximumStreamingGainDB: Double
        let minimumNoiseSuppressionDB: Double
        let maximumNoiseSuppressionDB: Double
        let transientCrestFactorThresholdDB: Double
        let minimumSpeechZeroCrossingRate: Double
        let maximumSpeechZeroCrossingRate: Double

        static let balanced = Self(
            sampleRate: 16_000,
            frameDurationSeconds: 0.02,
            ringBufferDurationSeconds: 0.32,
            minimumNoiseCalibrationFrameCount: 3,
            speechStartWindowFrameCount: 3,
            primarySpeechStartThreshold: 2,
            confirmationSpeechStartThreshold: 1,
            minimumLearnableNoiseFloorDBFS: -76,
            minimumSpeechRiseAboveNoiseFloorDB: 12,
            absoluteSpeechFloorDBFS: -58,
            minimumCommittedSpeechDurationSeconds: 0.3,
            endpointTrailingSilenceDurationSeconds: 0.7,
            primaryVADMode: .quality,
            confirmationVADMode: .aggressive,
            streamingGainTargetDBFS: -20,
            peakCeilingDBFS: -1,
            maximumStreamingGainDB: 12,
            minimumNoiseSuppressionDB: 8,
            maximumNoiseSuppressionDB: 30,
            transientCrestFactorThresholdDB: 18,
            minimumSpeechZeroCrossingRate: 0.02,
            maximumSpeechZeroCrossingRate: 0.08
        )

        var frameSize: Int {
            Int(sampleRate * frameDurationSeconds)
        }

        var ringBufferFrameCount: Int {
            Int(round(ringBufferDurationSeconds / frameDurationSeconds))
        }

        var minimumCommittedSpeechFrameCount: Int {
            Int(round(minimumCommittedSpeechDurationSeconds / frameDurationSeconds))
        }

        var endpointTrailingSilenceFrameCount: Int {
            Int(round(endpointTrailingSilenceDurationSeconds / frameDurationSeconds))
        }
    }

    struct ProcessResult: Sendable {
        let processedSamples: [Int16]
        let committedFrames: [[Int16]]
        let didDetectEndpoint: Bool
    }

    struct Summary: Sendable {
        let didCommitSpeech: Bool
        let committedFrameCount: Int
    }

    private struct BufferedFrame: Sendable {
        let frameIndex: Int
        let samples: [Int16]
        let primarySpeech: Bool
        let confirmationSpeech: Bool
        let isTransientNoise: Bool
        let isZeroCrossingNoise: Bool
        let isLowZeroCrossingNoise: Bool
        let rmsDBFS: Double
        let rawRMSDBFS: Double
    }

    private struct HPFState: Sendable {
        private let coefficient: Double
        private var previousInput = 0.0
        private var previousOutput = 0.0

        init(sampleRate: Double, cutoffFrequency: Double = 70) {
            let dt = 1 / sampleRate
            let rc = 1 / (2 * Double.pi * cutoffFrequency)
            self.coefficient = rc / (rc + dt)
        }

        mutating func process(_ sample: Int16) -> Int16 {
            let input = Double(sample) / Double(Int16.max)
            let output = coefficient * (previousOutput + input - previousInput)
            previousInput = input
            previousOutput = output
            let scaled = output * Double(Int16.max)
            return Int16(max(Double(Int16.min), min(scaled, Double(Int16.max))))
        }
    }

    private let configuration: Configuration
    private let primarySpeechDetector: SpeechDecisionProvider
    private let confirmationSpeechDetector: SpeechDecisionProvider
    private var hpfState: HPFState
    private var processedFrameCount = 0
    private var committedFrameCount = 0
    private var tailNonSpeechFrameCount = 0
    private var endpointDetected = false
    private var isCommittingSpeech = false
    private var activationFrameIndex: Int?
    private var ringBuffer: [BufferedFrame] = []
    private var recentFrames: [BufferedFrame] = []
    private var recentNoiseLevelsDBFS: [Double] = []
    private var noiseFloorDBFS = -72.0
    private var analyzedFrameCountSinceActivation = 0
    private var rawPrimarySpeechFrameCountSinceActivation = 0
    private var rawConfirmationSpeechFrameCountSinceActivation = 0
    private var acceptedPrimarySpeechFrameCountSinceActivation = 0
    private var acceptedConfirmationSpeechFrameCountSinceActivation = 0
    private var transientNoiseFrameCountSinceActivation = 0
    private var zeroCrossingNoiseFrameCountSinceActivation = 0
    private var lowZeroCrossingNoiseFrameCountSinceActivation = 0
    private var commitStartedFrameIndex: Int?
    private var commitStartRawRMSDBFS: Double?
    private var commitStartRawPeakDBFS: Double?
    private var commitStartZeroCrossingRate: Double?
    private var commitStartSpeechThresholdDBFS: Double?

    init(
        configuration: Configuration = .balanced,
        primarySpeechDetector: SpeechDecisionProvider? = nil,
        confirmationSpeechDetector: SpeechDecisionProvider? = nil
    ) throws {
        self.configuration = configuration
        if let primarySpeechDetector {
            self.primarySpeechDetector = primarySpeechDetector
        } else {
            let primaryVAD = try WebRTCVAD(
                sampleRate: Int(configuration.sampleRate.rounded()),
                mode: configuration.primaryVADMode
            )
            self.primarySpeechDetector = { frame in
                try primaryVAD.process(frame: frame)
            }
        }

        if let confirmationSpeechDetector {
            self.confirmationSpeechDetector = confirmationSpeechDetector
        } else {
            let confirmationVAD = try WebRTCVAD(
                sampleRate: Int(configuration.sampleRate.rounded()),
                mode: configuration.confirmationVADMode
            )
            self.confirmationSpeechDetector = { frame in
                try confirmationVAD.process(frame: frame)
            }
        }

        self.hpfState = HPFState(sampleRate: configuration.sampleRate)
    }

    func activateRecordingWindow() {
        guard activationFrameIndex == nil else { return }
        activationFrameIndex = processedFrameCount
        recentFrames.removeAll(keepingCapacity: true)
        recentNoiseLevelsDBFS.removeAll(keepingCapacity: true)
        tailNonSpeechFrameCount = 0
        endpointDetected = false
        noiseFloorDBFS = -72.0
        analyzedFrameCountSinceActivation = 0
        rawPrimarySpeechFrameCountSinceActivation = 0
        rawConfirmationSpeechFrameCountSinceActivation = 0
        acceptedPrimarySpeechFrameCountSinceActivation = 0
        acceptedConfirmationSpeechFrameCountSinceActivation = 0
        transientNoiseFrameCountSinceActivation = 0
        zeroCrossingNoiseFrameCountSinceActivation = 0
        lowZeroCrossingNoiseFrameCountSinceActivation = 0
        commitStartedFrameIndex = nil
        commitStartRawRMSDBFS = nil
        commitStartRawPeakDBFS = nil
        commitStartZeroCrossingRate = nil
        commitStartSpeechThresholdDBFS = nil
    }

    func process(frameSamples: [Int16]) throws -> ProcessResult {
        precondition(frameSamples.count == configuration.frameSize, "Unexpected frame size.")

        let highPassedSamples = frameSamples.map { hpfState.process($0) }
        let rawRMSDBFS = Self.rmsDBFS(for: highPassedSamples)
        let rawPeakDBFS = Self.peakDBFS(for: highPassedSamples)
        let zeroCrossingRate = Self.zeroCrossingRate(for: highPassedSamples)
        let (gainAdjustedSamples, gainDB) = applyNoiseAwareGain(to: highPassedSamples, rmsDBFS: rawRMSDBFS)
        let isTransientNoise = !isCommittingSpeech && Self.isLikelyTransientNoise(
            rmsDBFS: rawRMSDBFS,
            peakDBFS: rawPeakDBFS,
            crestFactorThresholdDB: configuration.transientCrestFactorThresholdDB
        )
        let isZeroCrossingNoise =
            !isCommittingSpeech &&
            zeroCrossingRate >= configuration.maximumSpeechZeroCrossingRate
        let isLowZeroCrossingNoise =
            !isCommittingSpeech &&
            zeroCrossingRate <= configuration.minimumSpeechZeroCrossingRate
        let rawPrimarySpeech = try primarySpeechDetector(ArraySlice(highPassedSamples))
        let rawConfirmationSpeech = try confirmationSpeechDetector(ArraySlice(highPassedSamples))
        let activityFloorDBFS = max(
            noiseFloorDBFS + (configuration.minimumSpeechRiseAboveNoiseFloorDB / 2),
            configuration.absoluteSpeechFloorDBFS - 12
        )
        let primarySpeech =
            rawPrimarySpeech &&
            rawRMSDBFS >= activityFloorDBFS &&
            !isTransientNoise &&
            !isLowZeroCrossingNoise &&
            !isZeroCrossingNoise
        let confirmationSpeech =
            rawConfirmationSpeech &&
            rawRMSDBFS >= activityFloorDBFS &&
            !isTransientNoise &&
            !isLowZeroCrossingNoise &&
            !isZeroCrossingNoise
        let speechDetected = primarySpeech || confirmationSpeech
        // Once the capture has committed, keep speech and strip everything else.
        let nonSpeechSamples: [Int16]
        if isCommittingSpeech || isTransientNoise {
            nonSpeechSamples = Array(repeating: 0, count: gainAdjustedSamples.count)
        } else {
            nonSpeechSamples = Self.applyGain(
                to: gainAdjustedSamples,
                gainDB: noiseSuppressionDB(
                    rmsDBFS: rawRMSDBFS,
                    activityFloorDBFS: activityFloorDBFS,
                    currentGainDB: gainDB
                )
            )
        }
        let processedSamples = speechDetected ? gainAdjustedSamples : nonSpeechSamples
        let rmsDBFS = Self.rmsDBFS(for: processedSamples)
        let bufferedFrame = BufferedFrame(
            frameIndex: processedFrameCount,
            samples: processedSamples,
            primarySpeech: primarySpeech,
            confirmationSpeech: confirmationSpeech,
            isTransientNoise: isTransientNoise,
            isZeroCrossingNoise: isZeroCrossingNoise,
            isLowZeroCrossingNoise: isLowZeroCrossingNoise,
            rmsDBFS: rmsDBFS,
            rawRMSDBFS: rawRMSDBFS
        )

        if let activationFrameIndex, processedFrameCount >= activationFrameIndex {
            analyzedFrameCountSinceActivation += 1
            if rawPrimarySpeech {
                rawPrimarySpeechFrameCountSinceActivation += 1
            }
            if rawConfirmationSpeech {
                rawConfirmationSpeechFrameCountSinceActivation += 1
            }
            if primarySpeech {
                acceptedPrimarySpeechFrameCountSinceActivation += 1
            }
            if confirmationSpeech {
                acceptedConfirmationSpeechFrameCountSinceActivation += 1
            }
            if isTransientNoise {
                transientNoiseFrameCountSinceActivation += 1
            }
            if isZeroCrossingNoise {
                zeroCrossingNoiseFrameCountSinceActivation += 1
            }
            if isLowZeroCrossingNoise {
                lowZeroCrossingNoiseFrameCountSinceActivation += 1
            }
        }

        remember(frame: bufferedFrame)
        updateNoiseFloor(using: bufferedFrame)

        var committedFrames: [[Int16]] = []
        let commitDecision = speechCommitDecision()
        if isCommittingSpeech {
            committedFrames.append(processedSamples)
            committedFrameCount += 1
        } else if commitDecision.shouldCommit {
            let speechStartFrameIndex = recentFrames.first(where: {
                $0.primarySpeech || $0.confirmationSpeech
            })?.frameIndex ?? processedFrameCount
            let commitFloorFrameIndex = activationFrameIndex ?? processedFrameCount
            let flushStartFrameIndex = max(
                commitFloorFrameIndex,
                speechStartFrameIndex - configuration.ringBufferFrameCount
            )
            committedFrames = ringBuffer
                .filter { $0.frameIndex >= flushStartFrameIndex }
                .map(\.samples)
            if !committedFrames.isEmpty {
                isCommittingSpeech = true
                committedFrameCount += committedFrames.count
                commitStartedFrameIndex = processedFrameCount
                commitStartRawRMSDBFS = rawRMSDBFS
                commitStartRawPeakDBFS = rawPeakDBFS
                commitStartZeroCrossingRate = zeroCrossingRate
                commitStartSpeechThresholdDBFS = commitDecision.speechThresholdDBFS
            }
        }

        let didDetectEndpoint = updateEndpointState(using: bufferedFrame)
        processedFrameCount += 1
        return ProcessResult(
            processedSamples: processedSamples,
            committedFrames: committedFrames,
            didDetectEndpoint: didDetectEndpoint
        )
    }

    func summary() -> Summary {
        Summary(
            didCommitSpeech: committedFrameCount > 0,
            committedFrameCount: committedFrameCount
        )
    }

    func diagnostics() -> Diagnostics {
        Diagnostics(
            analyzedFrameCountSinceActivation: analyzedFrameCountSinceActivation,
            rawPrimarySpeechFrameCount: rawPrimarySpeechFrameCountSinceActivation,
            rawConfirmationSpeechFrameCount: rawConfirmationSpeechFrameCountSinceActivation,
            acceptedPrimarySpeechFrameCount: acceptedPrimarySpeechFrameCountSinceActivation,
            acceptedConfirmationSpeechFrameCount: acceptedConfirmationSpeechFrameCountSinceActivation,
            transientNoiseFrameCount: transientNoiseFrameCountSinceActivation,
            zeroCrossingNoiseFrameCount: zeroCrossingNoiseFrameCountSinceActivation,
            lowZeroCrossingNoiseFrameCount: lowZeroCrossingNoiseFrameCountSinceActivation,
            noiseFloorDBFS: noiseFloorDBFS,
            commitStartedFrameIndex: commitStartedFrameIndex,
            commitStartRawRMSDBFS: commitStartRawRMSDBFS,
            commitStartRawPeakDBFS: commitStartRawPeakDBFS,
            commitStartZeroCrossingRate: commitStartZeroCrossingRate,
            commitStartSpeechThresholdDBFS: commitStartSpeechThresholdDBFS,
            committedFrameCount: committedFrameCount,
            endpointDetected: endpointDetected
        )
    }

    private func remember(frame: BufferedFrame) {
        ringBuffer.append(frame)
        if ringBuffer.count > configuration.ringBufferFrameCount {
            ringBuffer.removeFirst(ringBuffer.count - configuration.ringBufferFrameCount)
        }

        recentFrames.append(frame)
        if recentFrames.count > configuration.speechStartWindowFrameCount {
            recentFrames.removeFirst(recentFrames.count - configuration.speechStartWindowFrameCount)
        }
    }

    private func updateNoiseFloor(using frame: BufferedFrame) {
        guard activationFrameIndex != nil,
              !isCommittingSpeech,
              !frame.isTransientNoise,
              !frame.isZeroCrossingNoise,
              !frame.isLowZeroCrossingNoise,
              frame.rawRMSDBFS.isFinite,
              frame.rawRMSDBFS >= configuration.minimumLearnableNoiseFloorDBFS else {
            return
        }

        let speechThresholdDBFS = max(
            noiseFloorDBFS + configuration.minimumSpeechRiseAboveNoiseFloorDB,
            configuration.absoluteSpeechFloorDBFS
        )
        let learnableNoiseCeilingDBFS = speechThresholdDBFS + 4
        guard frame.rawRMSDBFS <= learnableNoiseCeilingDBFS else {
            return
        }

        recentNoiseLevelsDBFS.append(frame.rawRMSDBFS)
        if recentNoiseLevelsDBFS.count > 50 {
            recentNoiseLevelsDBFS.removeFirst(recentNoiseLevelsDBFS.count - 50)
        }

        if let percentile = Self.percentile(recentNoiseLevelsDBFS, fraction: 0.2) {
            noiseFloorDBFS = max(percentile, configuration.minimumLearnableNoiseFloorDBFS)
        }
    }

    private func applyNoiseAwareGain(
        to samples: [Int16],
        rmsDBFS: Double
    ) -> (samples: [Int16], gainDB: Double) {
        let gainDB = recommendedGainDB(for: samples, rmsDBFS: rmsDBFS)
        return (Self.applyGain(to: samples, gainDB: gainDB), gainDB)
    }

    private func noiseSuppressionDB(
        rmsDBFS: Double,
        activityFloorDBFS: Double,
        currentGainDB: Double
    ) -> Double {
        guard rmsDBFS.isFinite else {
            return -configuration.maximumNoiseSuppressionDB
        }

        let distanceBelowFloor = max(0, activityFloorDBFS - rmsDBFS)
        let suppressionDB = min(
            configuration.maximumNoiseSuppressionDB,
            configuration.minimumNoiseSuppressionDB + (distanceBelowFloor * 2)
        )

        return min(-suppressionDB, -currentGainDB)
    }

    private func recommendedGainDB(for samples: [Int16], rmsDBFS: Double) -> Double {
        guard rmsDBFS.isFinite else { return 0 }

        let speechActivationFloor = max(
            noiseFloorDBFS + configuration.minimumSpeechRiseAboveNoiseFloorDB,
            configuration.absoluteSpeechFloorDBFS
        )
        guard rmsDBFS >= speechActivationFloor else {
            return 0
        }

        let peakDBFS = Self.peakDBFS(for: samples)
        let availableHeadroomDB = configuration.peakCeilingDBFS - peakDBFS
        guard availableHeadroomDB > 0 else {
            return 0
        }

        return max(
            0,
            min(
                configuration.streamingGainTargetDBFS - rmsDBFS,
                configuration.maximumStreamingGainDB,
                availableHeadroomDB
            )
        )
    }

    private func speechCommitDecision() -> (shouldCommit: Bool, speechThresholdDBFS: Double?) {
        guard let activationFrameIndex,
              analyzedFrameCountSinceActivation >= configuration.minimumNoiseCalibrationFrameCount,
              recentFrames.count == configuration.speechStartWindowFrameCount,
              recentFrames.first?.frameIndex ?? 0 >= activationFrameIndex,
              let currentFrame = recentFrames.last,
              (currentFrame.primarySpeech || currentFrame.confirmationSpeech),
              !currentFrame.isTransientNoise else {
            return (false, nil)
        }

        let primaryPositiveCount = recentFrames.filter { $0.primarySpeech }.count
        let confirmationPositiveCount = recentFrames.filter { $0.confirmationSpeech }.count
        let speechThreshold = max(
            noiseFloorDBFS + configuration.minimumSpeechRiseAboveNoiseFloorDB,
            configuration.absoluteSpeechFloorDBFS
        )

        let shouldCommit =
            primaryPositiveCount >= configuration.primarySpeechStartThreshold &&
            confirmationPositiveCount >= configuration.confirmationSpeechStartThreshold &&
            currentFrame.rawRMSDBFS >= speechThreshold
        return (shouldCommit, speechThreshold)
    }

    private static func isLikelyTransientNoise(
        rmsDBFS: Double,
        peakDBFS: Double,
        crestFactorThresholdDB: Double
    ) -> Bool {
        guard rmsDBFS.isFinite, peakDBFS.isFinite else {
            return true
        }

        return (peakDBFS - rmsDBFS) >= crestFactorThresholdDB
    }

    private func updateEndpointState(using frame: BufferedFrame) -> Bool {
        guard activationFrameIndex != nil,
              isCommittingSpeech,
              !endpointDetected,
              committedFrameCount >= configuration.minimumCommittedSpeechFrameCount else {
            return false
        }

        let isDefinitiveSilence = frame.rmsDBFS <= (configuration.absoluteSpeechFloorDBFS - 32)
        if isDefinitiveSilence || (!frame.primarySpeech && !frame.confirmationSpeech) {
            tailNonSpeechFrameCount += 1
        } else {
            tailNonSpeechFrameCount = 0
        }

        guard tailNonSpeechFrameCount >= configuration.endpointTrailingSilenceFrameCount else {
            return false
        }

        endpointDetected = true
        return true
    }

    private static func rmsDBFS(for samples: [Int16]) -> Double {
        guard !samples.isEmpty else { return -160 }

        var sumSquares = 0.0
        for sample in samples {
            let normalized = Double(sample) / Double(Int16.max)
            sumSquares += normalized * normalized
        }

        let rms = sqrt(sumSquares / Double(samples.count))
        guard rms.isFinite, rms > 0 else { return -160 }
        return 20 * log10(rms)
    }

    private static func peakDBFS(for samples: [Int16]) -> Double {
        guard !samples.isEmpty else { return -160 }

        let peakAmplitude = samples.reduce(0.0) { partialResult, sample in
            max(partialResult, abs(Double(sample)) / Double(Int16.max))
        }
        guard peakAmplitude.isFinite, peakAmplitude > 0 else { return -160 }
        return 20 * log10(peakAmplitude)
    }

    private static func zeroCrossingRate(for samples: [Int16]) -> Double {
        guard samples.count > 1 else { return 0 }

        var crossingCount = 0
        var previousSample = samples[0]

        for sample in samples.dropFirst() {
            let didCrossZero =
                (previousSample < 0 && sample >= 0) ||
                (previousSample > 0 && sample <= 0)
            if didCrossZero {
                crossingCount += 1
            }
            previousSample = sample
        }

        return Double(crossingCount) / Double(samples.count - 1)
    }

    private static func applyGain(to samples: [Int16], gainDB: Double) -> [Int16] {
        guard gainDB != 0 else { return samples }

        let multiplier = pow(10, gainDB / 20)
        return samples.map { sample in
            let amplified = Double(sample) * multiplier
            return Int16(max(Double(Int16.min), min(amplified, Double(Int16.max))))
        }
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
}
