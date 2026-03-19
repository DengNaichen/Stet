import Foundation

final class StreamingSpeechCaptureFrontend: @unchecked Sendable {
    typealias SpeechDecisionProvider = @Sendable (ArraySlice<Int16>) throws -> Bool

    struct Configuration: Sendable {
        let sampleRate: Double
        let frameDurationSeconds: Double
        let ringBufferDurationSeconds: Double
        let speechStartWindowFrameCount: Int
        let primarySpeechStartThreshold: Int
        let confirmationSpeechStartThreshold: Int
        let minimumSpeechRiseAboveNoiseFloorDB: Double
        let absoluteSpeechFloorDBFS: Double
        let minimumCommittedSpeechDurationSeconds: Double
        let endpointTrailingSilenceDurationSeconds: Double
        let primaryVADMode: WebRTCVADMode
        let confirmationVADMode: WebRTCVADMode
        let streamingGainTargetDBFS: Double
        let peakCeilingDBFS: Double
        let maximumStreamingGainDB: Double

        static let balanced = Self(
            sampleRate: 16_000,
            frameDurationSeconds: 0.02,
            ringBufferDurationSeconds: 0.32,
            speechStartWindowFrameCount: 3,
            primarySpeechStartThreshold: 2,
            confirmationSpeechStartThreshold: 1,
            minimumSpeechRiseAboveNoiseFloorDB: 6,
            absoluteSpeechFloorDBFS: -58,
            minimumCommittedSpeechDurationSeconds: 0.3,
            endpointTrailingSilenceDurationSeconds: 0.7,
            primaryVADMode: .quality,
            confirmationVADMode: .aggressive,
            streamingGainTargetDBFS: -20,
            peakCeilingDBFS: -1,
            maximumStreamingGainDB: 12
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
        tailNonSpeechFrameCount = 0
        endpointDetected = false
    }

    func process(frameSamples: [Int16]) throws -> ProcessResult {
        precondition(frameSamples.count == configuration.frameSize, "Unexpected frame size.")

        let highPassedSamples = frameSamples.map { hpfState.process($0) }
        let rawRMSDBFS = Self.rmsDBFS(for: highPassedSamples)
        let processedSamples = applyNoiseAwareGain(to: highPassedSamples, rmsDBFS: rawRMSDBFS)
        let rmsDBFS = Self.rmsDBFS(for: processedSamples)
        let rawPrimarySpeech = try primarySpeechDetector(ArraySlice(processedSamples))
        let rawConfirmationSpeech = try confirmationSpeechDetector(ArraySlice(processedSamples))
        let activityFloorDBFS = max(
            noiseFloorDBFS + (configuration.minimumSpeechRiseAboveNoiseFloorDB / 2),
            configuration.absoluteSpeechFloorDBFS - 12
        )
        let primarySpeech = rawPrimarySpeech && rmsDBFS >= activityFloorDBFS
        let confirmationSpeech = rawConfirmationSpeech && rmsDBFS >= activityFloorDBFS
        let bufferedFrame = BufferedFrame(
            frameIndex: processedFrameCount,
            samples: processedSamples,
            primarySpeech: primarySpeech,
            confirmationSpeech: confirmationSpeech,
            rmsDBFS: rmsDBFS,
            rawRMSDBFS: rawRMSDBFS
        )

        remember(frame: bufferedFrame)
        updateNoiseFloor(using: bufferedFrame)

        var committedFrames: [[Int16]] = []
        if isCommittingSpeech {
            committedFrames.append(processedSamples)
            committedFrameCount += 1
        } else if shouldStartSpeechCommit() {
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
        guard !frame.primarySpeech, !frame.confirmationSpeech else {
            return
        }

        recentNoiseLevelsDBFS.append(frame.rawRMSDBFS)
        if recentNoiseLevelsDBFS.count > 50 {
            recentNoiseLevelsDBFS.removeFirst(recentNoiseLevelsDBFS.count - 50)
        }

        if let percentile = Self.percentile(recentNoiseLevelsDBFS, fraction: 0.2) {
            noiseFloorDBFS = percentile
        }
    }

    private func applyNoiseAwareGain(to samples: [Int16], rmsDBFS: Double) -> [Int16] {
        let gainDB = recommendedGainDB(for: samples, rmsDBFS: rmsDBFS)
        guard gainDB > 0 else { return samples }

        let multiplier = pow(10, gainDB / 20)
        return samples.map { sample in
            let amplified = Double(sample) * multiplier
            return Int16(max(Double(Int16.min), min(amplified, Double(Int16.max))))
        }
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

    private func shouldStartSpeechCommit() -> Bool {
        guard let activationFrameIndex,
              recentFrames.count == configuration.speechStartWindowFrameCount,
              recentFrames.first?.frameIndex ?? 0 >= activationFrameIndex,
              let currentFrame = recentFrames.last,
              currentFrame.primarySpeech || currentFrame.confirmationSpeech else {
            return false
        }

        let primaryPositiveCount = recentFrames.filter { $0.primarySpeech }.count
        let confirmationPositiveCount = recentFrames.filter { $0.confirmationSpeech }.count
        let speechThreshold = max(
            noiseFloorDBFS + configuration.minimumSpeechRiseAboveNoiseFloorDB,
            configuration.absoluteSpeechFloorDBFS
        )

        return primaryPositiveCount >= configuration.primarySpeechStartThreshold &&
            confirmationPositiveCount >= configuration.confirmationSpeechStartThreshold &&
            currentFrame.rmsDBFS >= speechThreshold
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
