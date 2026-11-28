import Accelerate
@preconcurrency import CoreML
import Foundation

// MARK: - SpeechBrain 60-bin Log-Mel Frontend

/// Independent SpeechBrain-compatible 60-bin log-mel spectrogram extractor.
/// Matches `speechbrain/lang-id-voxlingua107-ecapa` (16 kHz, 400-pt periodic Hamming,
/// 160-pt hop, center zero-pad, symmetric triangular mel filterbank, top_db=80, sentence CMN).
nonisolated final class SpeechBrainFbank: @unchecked Sendable {
    static let sampleRate = 16_000
    static let nFFT = 400
    static let winLength = 400
    static let hopLength = 160
    static let nFreqs = nFFT / 2 + 1  // 201
    static let nMels = 60

    private let window: [Float]
    /// Column-oriented DFT twiddle matrices stored as `[nFFT, nFreqs]` row-major for `vDSP_mmul`.
    private let cosMatrixT: [Float]
    private let sinMatrixT: [Float]
    /// SpeechBrain symmetric triangular filterbank stored as `[nFreqs, nMels]` row-major for `vDSP_mmul`.
    private let melFilterbankT: [Float]

    init() {
        var win = [Float](repeating: 0, count: Self.winLength)
        for index in 0..<Self.winLength {
            win[index] = 0.54 - 0.46 * cos(2.0 * Float.pi * Float(index) / Float(Self.winLength))
        }
        self.window = win

        var cosMT = [Float](repeating: 0, count: Self.nFFT * Self.nFreqs)
        var sinMT = [Float](repeating: 0, count: Self.nFFT * Self.nFreqs)
        let twoPiOverN = 2.0 * Double.pi / Double(Self.nFFT)
        for sampleIndex in 0..<Self.nFFT {
            let rowOffset = sampleIndex * Self.nFreqs
            for freqIndex in 0..<Self.nFreqs {
                let angle = twoPiOverN * Double(freqIndex * sampleIndex)
                cosMT[rowOffset + freqIndex] = Float(cos(angle))
                sinMT[rowOffset + freqIndex] = Float(-sin(angle))
            }
        }
        self.cosMatrixT = cosMT
        self.sinMatrixT = sinMT

        func hzToMel(_ hz: Double) -> Double { 2595.0 * log10(1.0 + hz / 700.0) }
        func melToHz(_ mel: Double) -> Double { 700.0 * (pow(10.0, mel / 2595.0) - 1.0) }

        let melLow = hzToMel(0.0)
        let melHigh = hzToMel(Double(Self.sampleRate) / 2.0)
        var hzPoints = [Double](repeating: 0, count: Self.nMels + 2)
        for index in 0..<(Self.nMels + 2) {
            let frac = Double(index) / Double(Self.nMels + 1)
            hzPoints[index] = melToHz(melLow + frac * (melHigh - melLow))
        }

        var frequencies = [Double](repeating: 0, count: Self.nFreqs)
        for freqIndex in 0..<Self.nFreqs {
            frequencies[freqIndex] = Double(freqIndex) * (Double(Self.sampleRate) / 2.0) / Double(Self.nFreqs - 1)
        }

        var fbT = [Float](repeating: 0, count: Self.nFreqs * Self.nMels)
        for melIndex in 0..<Self.nMels {
            let center = hzPoints[melIndex + 1]
            let band = hzPoints[melIndex + 1] - hzPoints[melIndex]
            for freqIndex in 0..<Self.nFreqs {
                let slope = (frequencies[freqIndex] - center) / band
                let value = max(0.0, min(slope + 1.0, -slope + 1.0))
                fbT[freqIndex * Self.nMels + melIndex] = Float(value)
            }
        }
        self.melFilterbankT = fbT
    }

    func compute(samples: [Float], applySentenceMeanNormalization: Bool = true) -> (frameCount: Int, features: [Float])
    {
        guard !samples.isEmpty else { return (0, []) }

        let pad = Self.nFFT / 2
        var padded = [Float](repeating: 0, count: samples.count + 2 * pad)
        padded.replaceSubrange(pad..<(pad + samples.count), with: samples)
        if padded.count < Self.nFFT {
            padded.append(contentsOf: repeatElement(0, count: Self.nFFT - padded.count))
        }
        let numFrames = (padded.count - Self.nFFT) / Self.hopLength + 1

        var windowed = [Float](repeating: 0, count: numFrames * Self.nFFT)
        padded.withUnsafeBufferPointer { padBuf in
            window.withUnsafeBufferPointer { winBuf in
                windowed.withUnsafeMutableBufferPointer { outBuf in
                    guard let padBase = padBuf.baseAddress,
                        let winBase = winBuf.baseAddress,
                        let outBase = outBuf.baseAddress
                    else { return }
                    for frameIndex in 0..<numFrames {
                        vDSP_vmul(
                            padBase + frameIndex * Self.hopLength, 1,
                            winBase, 1,
                            outBase + frameIndex * Self.nFFT, 1,
                            vDSP_Length(Self.nFFT)
                        )
                    }
                }
            }
        }

        // Exact 400-pt DFT via matrix multiply: [numFrames, nFFT] x [nFFT, nFreqs] -> [numFrames, nFreqs]
        var realPart = [Float](repeating: 0, count: numFrames * Self.nFreqs)
        var imagPart = [Float](repeating: 0, count: numFrames * Self.nFreqs)
        vDSP_mmul(
            windowed, 1,
            cosMatrixT, 1,
            &realPart, 1,
            vDSP_Length(numFrames), vDSP_Length(Self.nFreqs), vDSP_Length(Self.nFFT)
        )
        vDSP_mmul(
            windowed, 1,
            sinMatrixT, 1,
            &imagPart, 1,
            vDSP_Length(numFrames), vDSP_Length(Self.nFreqs), vDSP_Length(Self.nFFT)
        )

        var power = [Float](repeating: 0, count: numFrames * Self.nFreqs)
        var imagSquared = [Float](repeating: 0, count: numFrames * Self.nFreqs)
        vDSP_vsq(realPart, 1, &power, 1, vDSP_Length(power.count))
        vDSP_vsq(imagPart, 1, &imagSquared, 1, vDSP_Length(imagSquared.count))
        vDSP_vadd(power, 1, imagSquared, 1, &power, 1, vDSP_Length(power.count))

        // Mel projection: [numFrames, nFreqs] x [nFreqs, nMels] -> [numFrames, nMels]
        var mel = [Float](repeating: 0, count: numFrames * Self.nMels)
        vDSP_mmul(
            power, 1,
            melFilterbankT, 1,
            &mel, 1,
            vDSP_Length(numFrames), vDSP_Length(Self.nMels), vDSP_Length(Self.nFreqs)
        )

        var maxDB = -Float.greatestFiniteMagnitude
        for index in 0..<mel.count {
            let decibels = 10.0 * log10(max(mel[index], 1e-10))
            mel[index] = decibels
            if decibels > maxDB {
                maxDB = decibels
            }
        }
        let floorDB = maxDB - 80.0
        for index in 0..<mel.count where mel[index] < floorDB {
            mel[index] = floorDB
        }

        if applySentenceMeanNormalization, numFrames > 0 {
            let invFrames = 1.0 / Float(numFrames)
            for melIndex in 0..<Self.nMels {
                var sum: Float = 0
                for frameIndex in 0..<numFrames {
                    sum += mel[frameIndex * Self.nMels + melIndex]
                }
                let mean = sum * invFrames
                for frameIndex in 0..<numFrames {
                    mel[frameIndex * Self.nMels + melIndex] -= mean
                }
            }
        }

        return (numFrames, mel)
    }
}

// MARK: - Prefix Activity Detector (LID Evidence Only)

/// Estimates active speech onset and duration on short 10 ms PCM windows with an
/// adaptive noise floor. Used strictly to select the prefix sent to LID; audio
/// forwarded to Apple Speech is never trimmed.
nonisolated struct SpeechPrefixActivity: Sendable, Equatable {
    let onsetSampleIndex: Int
    let activeSpeechSeconds: Double
    let totalSeconds: Double
}

nonisolated struct SpeechPrefixActivityDetector: Sendable {
    let sampleRate: Int
    let frameSize: Int
    let leadInFrames: Int
    let minRMSFloor: Float
    let maxNoiseFloor: Float
    let minSpeechThreshold: Float
    let noiseMultiplier: Float

    init(
        sampleRate: Int = SpeechBrainFbank.sampleRate,
        frameSize: Int = 160,
        leadInFrames: Int = 2,
        minRMSFloor: Float = 0.004,
        maxNoiseFloor: Float = 0.030,
        minSpeechThreshold: Float = 0.012,
        noiseMultiplier: Float = 2.0
    ) {
        self.sampleRate = sampleRate
        self.frameSize = frameSize
        self.leadInFrames = leadInFrames
        self.minRMSFloor = minRMSFloor
        self.maxNoiseFloor = maxNoiseFloor
        self.minSpeechThreshold = minSpeechThreshold
        self.noiseMultiplier = noiseMultiplier
    }

    func analyze(samples: [Float]) -> SpeechPrefixActivity {
        let totalSeconds = Double(samples.count) / Double(sampleRate)
        guard samples.count >= frameSize else {
            return SpeechPrefixActivity(onsetSampleIndex: 0, activeSpeechSeconds: 0, totalSeconds: totalSeconds)
        }

        let frameCount = samples.count / frameSize
        var frameRMS = [Float](repeating: 0, count: frameCount)
        samples.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            for index in 0..<frameCount {
                var rms: Float = 0
                vDSP_rmsqv(base + index * frameSize, 1, &rms, vDSP_Length(frameSize))
                frameRMS[index] = rms
            }
        }

        let sortedRMS = frameRMS.sorted()
        let noiseIndex = min(sortedRMS.count - 1, max(0, sortedRMS.count / 10))
        // Clamp estimated noise floor so continuous speech from sample 0 is never mistaken for background noise.
        let noiseFloor = min(maxNoiseFloor, max(minRMSFloor, sortedRMS[noiseIndex]))
        let threshold = max(minSpeechThreshold, noiseFloor * noiseMultiplier)

        var firstSpeechFrame: Int?
        var activeFrames = 0
        for (index, rms) in frameRMS.enumerated() where rms >= threshold {
            if firstSpeechFrame == nil {
                firstSpeechFrame = index
            }
            activeFrames += 1
        }

        let onsetFrame = max(0, (firstSpeechFrame ?? 0) - leadInFrames)
        let activeSeconds = Double(activeFrames * frameSize) / Double(sampleRate)
        return SpeechPrefixActivity(
            onsetSampleIndex: onsetFrame * frameSize,
            activeSpeechSeconds: activeSeconds,
            totalSeconds: totalSeconds
        )
    }

    func extractLIDWindow(from samples: [Float], maxWindowSamples: Int) -> (
        window: [Float], activity: SpeechPrefixActivity
    ) {
        let activity = analyze(samples: samples)
        let start = min(activity.onsetSampleIndex, samples.count)
        let end = min(samples.count, start + maxWindowSamples)
        return (Array(samples[start..<end]), activity)
    }
}

// MARK: - Language Routing Policy

nonisolated struct SpokenLanguageScores: Sendable, Equatable {
    /// Log-probabilities indexed by VoxLingua107 label ID (107 entries), or sparse map by code.
    let logProbabilitiesByCode: [String: Double]
    let fbankMs: Double
    let inferenceMs: Double

    func probability(for code: String) -> Double {
        guard let logProb = logProbabilitiesByCode[code] else { return 0 }
        return exp(logProb)
    }

    var totalInferenceMs: Double { fbankMs + inferenceMs }
}

nonisolated enum LanguageRoutingReason: String, Sendable, Equatable {
    case singleLanguageBypass
    case sameIdentifierBypass
    case lidUnavailableFallback
    case lidFailedFallback
    case lidTimeoutFallback
    case insufficientSpeechFallback
    case lowCandidateMassFallback
    case earlyLockPrimary
    case earlyLockSecondary
    case finalPrimary
    case finalSecondary
    case wallClockDeadlineFallback
}

nonisolated struct LanguageRoutingDecision: Sendable, Equatable {
    let selectedLanguage: SpeechRecognitionLanguage
    let reason: LanguageRoutingReason
    let secondaryConditionalProbability: Double?
    let candidatePairMass: Double?
    let activeSpeechSeconds: Double
}

nonisolated struct LanguageRoutingPolicy: Sendable {
    /// Minimum active speech needed before a final (e.g. stop-triggered) routing decision can switch away from primary.
    let minActiveSpeechForDecision: Double
    /// Active speech target for optional early lock if confidence is extreme.
    let earlyLockSpeechSeconds: Double
    /// Active speech target for full streaming decision lock.
    let standardLockSpeechSeconds: Double
    /// Maximum audio window passed into LID (seconds after onset).
    let maxLIDWindowSeconds: Double
    /// Wall-clock deadline from first audio frame before falling back to primary.
    let wallClockDeadlineSeconds: Double
    /// Minimum combined 107-way probability mass `P_107(primary) + P_107(secondary)` to guard against noise/third-language renormalization.
    let minCandidatePairMass: Double
    /// Asymmetric conditional probability threshold when primary is Chinese and secondary is English.
    let chinesePrimaryEnglishThreshold: Double
    /// General conditional probability threshold for non-Chinese primary pairs.
    let defaultSecondaryThreshold: Double
    /// Extreme conditional probability threshold for early lock at `earlyLockSpeechSeconds`.
    let earlyLockThreshold: Double

    static let `default` = LanguageRoutingPolicy(
        minActiveSpeechForDecision: 0.35,
        earlyLockSpeechSeconds: 1.0,
        standardLockSpeechSeconds: 1.5,
        maxLIDWindowSeconds: 2.0,
        wallClockDeadlineSeconds: 2.5,
        minCandidatePairMass: 0.02,
        chinesePrimaryEnglishThreshold: 0.85,
        defaultSecondaryThreshold: 0.80,
        earlyLockThreshold: 0.95
    )

    /// Evaluates whether a streaming prefix can lock early or make its final decision.
    /// Returns `nil` when `isFinalWindow == false` and more speech should be accumulated.
    func evaluate(
        primary: SpeechRecognitionLanguage,
        secondary: SpeechRecognitionLanguage,
        scores: SpokenLanguageScores,
        activeSpeechSeconds: Double,
        isFinalWindow: Bool
    ) -> LanguageRoutingDecision? {
        let primaryCode = primary.voxLinguaCode
        let secondaryCode = secondary.voxLinguaCode
        guard primaryCode != secondaryCode else {
            return LanguageRoutingDecision(
                selectedLanguage: primary,
                reason: .sameIdentifierBypass,
                secondaryConditionalProbability: nil,
                candidatePairMass: nil,
                activeSpeechSeconds: activeSpeechSeconds
            )
        }

        guard activeSpeechSeconds >= minActiveSpeechForDecision else {
            guard isFinalWindow else { return nil }
            return LanguageRoutingDecision(
                selectedLanguage: primary,
                reason: .insufficientSpeechFallback,
                secondaryConditionalProbability: nil,
                candidatePairMass: nil,
                activeSpeechSeconds: activeSpeechSeconds
            )
        }

        let pPrimary = scores.probability(for: primaryCode)
        let pSecondary = scores.probability(for: secondaryCode)
        let pairMass = pPrimary + pSecondary

        guard pairMass >= minCandidatePairMass else {
            guard isFinalWindow else { return nil }
            return LanguageRoutingDecision(
                selectedLanguage: primary,
                reason: .lowCandidateMassFallback,
                secondaryConditionalProbability: nil,
                candidatePairMass: pairMass,
                activeSpeechSeconds: activeSpeechSeconds
            )
        }

        let pSecondaryGivenPair = pSecondary / pairMass

        if !isFinalWindow {
            guard activeSpeechSeconds >= earlyLockSpeechSeconds else { return nil }
            if pSecondaryGivenPair >= earlyLockThreshold {
                return LanguageRoutingDecision(
                    selectedLanguage: secondary,
                    reason: .earlyLockSecondary,
                    secondaryConditionalProbability: pSecondaryGivenPair,
                    candidatePairMass: pairMass,
                    activeSpeechSeconds: activeSpeechSeconds
                )
            }
            if pSecondaryGivenPair <= (1.0 - earlyLockThreshold) {
                return LanguageRoutingDecision(
                    selectedLanguage: primary,
                    reason: .earlyLockPrimary,
                    secondaryConditionalProbability: pSecondaryGivenPair,
                    candidatePairMass: pairMass,
                    activeSpeechSeconds: activeSpeechSeconds
                )
            }
            return nil
        }

        let switchThreshold: Double =
            (primary.voxLinguaCode == "zh" && secondary.voxLinguaCode == "en")
            ? chinesePrimaryEnglishThreshold
            : defaultSecondaryThreshold

        if pSecondaryGivenPair >= switchThreshold {
            return LanguageRoutingDecision(
                selectedLanguage: secondary,
                reason: .finalSecondary,
                secondaryConditionalProbability: pSecondaryGivenPair,
                candidatePairMass: pairMass,
                activeSpeechSeconds: activeSpeechSeconds
            )
        }

        return LanguageRoutingDecision(
            selectedLanguage: primary,
            reason: .finalPrimary,
            secondaryConditionalProbability: pSecondaryGivenPair,
            candidatePairMass: pairMass,
            activeSpeechSeconds: activeSpeechSeconds
        )
    }
}

extension SpeechRecognitionLanguage {
    nonisolated var voxLinguaCode: String {
        switch self {
        case .chineseSimplified, .chineseTraditional: "zh"
        case .englishUS: "en"
        case .japanese: "ja"
        case .korean: "ko"
        }
    }
}

// MARK: - Spoken Language Identifier Protocol & Core ML Implementation

nonisolated protocol SpokenLanguageIdentifying: AnyObject, Sendable {
    var isModelAvailable: Bool { get }
    func preload() async
    func identify(samples: [Float]) async throws -> SpokenLanguageScores
    func unload()
}

nonisolated final class CoreMLSpokenLanguageIdentifier: SpokenLanguageIdentifying, @unchecked Sendable {
    /// VoxLingua107 stable class indices for StetMobile's supported languages.
    static let classIndexByCode: [String: Int] = [
        "en": 20,
        "ja": 45,
        "ko": 51,
        "zh": 106,
    ]

    static let defaultModelFileName = "EcapaLid107.mlmodelc"
    static let defaultPackageFileName = "EcapaLid107.mlpackage"

    private struct LoadedModel {
        let model: MLModel
        let outputName: String
        let applyCMN: Bool
    }

    private let modelURLProvider: @Sendable () -> URL?
    private let fbank = SpeechBrainFbank()
    private let lock = NSLock()
    private var loaded: LoadedModel?
    private var loadTask: Task<LoadedModel?, Never>?

    init(modelURLProvider: @escaping @Sendable () -> URL? = CoreMLSpokenLanguageIdentifier.defaultModelURL) {
        self.modelURLProvider = modelURLProvider
    }

    var isModelAvailable: Bool {
        lock.lock()
        let hasLoaded = loaded != nil
        lock.unlock()
        return hasLoaded || modelURLProvider() != nil
    }

    func preload() async {
        _ = await loadModelIfAvailable()
    }

    func unload() {
        lock.lock()
        let task = loadTask
        loadTask = nil
        loaded = nil
        lock.unlock()
        task?.cancel()
    }

    func identify(samples: [Float]) async throws -> SpokenLanguageScores {
        guard !samples.isEmpty else {
            throw IdentifierError.emptyAudio
        }
        guard let loadedModel = await loadModelIfAvailable() else {
            throw IdentifierError.modelUnavailable
        }

        // Run feature extraction and synchronous Core ML CPU inference strictly off MainActor.
        return try await Task.detached(priority: .userInitiated) { [fbank] in
            try Task.checkCancellation()

            let t0 = ContinuousClock.now
            let (frameCount, features) = fbank.compute(
                samples: samples,
                applySentenceMeanNormalization: loadedModel.applyCMN
            )
            let t1 = ContinuousClock.now
            guard frameCount >= 10 else {
                throw IdentifierError.audioTooShort
            }

            let inputArray = try MLMultiArray(
                shape: [1, NSNumber(value: frameCount), NSNumber(value: SpeechBrainFbank.nMels)],
                dataType: .float32
            )
            features.withUnsafeBufferPointer { src in
                guard let base = src.baseAddress else { return }
                let dst = inputArray.dataPointer.assumingMemoryBound(to: Float.self)
                dst.update(from: base, count: features.count)
            }

            let provider = try MLDictionaryFeatureProvider(dictionary: [
                "mel_features": MLFeatureValue(multiArray: inputArray)
            ])
            let output = try loadedModel.model.prediction(from: provider)
            let t2 = ContinuousClock.now

            guard let logits = output.featureValue(for: loadedModel.outputName)?.multiArrayValue else {
                throw IdentifierError.invalidModelOutput
            }

            let count = logits.count
            let pointer = logits.dataPointer.assumingMemoryBound(to: Float.self)
            var scoresByCode: [String: Double] = [:]
            scoresByCode.reserveCapacity(Self.classIndexByCode.count)
            for (code, index) in Self.classIndexByCode where index < count {
                scoresByCode[code] = Double(pointer[index])
            }

            return SpokenLanguageScores(
                logProbabilitiesByCode: scoresByCode,
                fbankMs: Self.milliseconds(t1 - t0),
                inferenceMs: Self.milliseconds(t2 - t1)
            )
        }.value
    }

    private func loadModelIfAvailable() async -> LoadedModel? {
        let task: Task<LoadedModel?, Never> = lock.withLock {
            if let loaded {
                return Task { loaded }
            }
            if let existing = loadTask {
                return existing
            }
            let newTask = Task.detached(priority: .utility) { [weak self] () -> LoadedModel? in
                guard let self, let url = self.modelURLProvider() else { return nil }
                do {
                    let compiledURL = try Self.resolveCompiledModelURL(from: url)
                    let config = MLModelConfiguration()
                    // Background iOS audio execution forbids Metal GPU command buffers;
                    // CPU-only is both background-safe and fastest for this small 1D CNN.
                    config.computeUnits = .cpuOnly
                    let model = try MLModel(contentsOf: compiledURL, configuration: config)
                    let outputName =
                        model.modelDescription.outputDescriptionsByName.keys.first ?? "log_probabilities"
                    // Only skip external CMN if model metadata explicitly declares graph-internal CMN.
                    let metadata = model.modelDescription.metadata[.creatorDefinedKey] as? [String: String]
                    let internalCMN = metadata?["stet.lid.internal_cmn"] == "true"
                    let loadedModel = LoadedModel(
                        model: model,
                        outputName: outputName,
                        applyCMN: !internalCMN
                    )
                    self.lock.withLock {
                        if !Task.isCancelled {
                            self.loaded = loadedModel
                        }
                        self.loadTask = nil
                    }
                    return loadedModel
                } catch {
                    self.lock.withLock {
                        self.loadTask = nil
                    }
                    return nil
                }
            }
            loadTask = newTask
            return newTask
        }
        return await task.value
    }

    private static func resolveCompiledModelURL(from url: URL) throws -> URL {
        if url.pathExtension == "mlmodelc" {
            return url
        }
        // Compile portable .mlpackage on device into versioned Application Support cache.
        let compiledTemp = try MLModel.compileModel(at: url)
        guard let cacheDir = Self.compiledModelDirectory() else {
            return compiledTemp
        }
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        let target = cacheDir.appendingPathComponent(defaultModelFileName, isDirectory: true)
        let staged = cacheDir.appendingPathComponent(
            "\(defaultModelFileName).staging-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.copyItem(at: compiledTemp, to: staged)
        if FileManager.default.fileExists(atPath: target.path) {
            _ = try FileManager.default.replaceItemAt(target, withItemAt: staged)
        } else {
            try FileManager.default.moveItem(at: staged, to: target)
        }
        return target
    }

    static func compiledModelDirectory(
        fileManager: FileManager = .default
    ) -> URL? {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("StetMobile", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent("LID", isDirectory: true)
    }

    static func defaultModelURL() -> URL? {
        let fm = FileManager.default
        if let dir = compiledModelDirectory(fileManager: fm) {
            let compiled = dir.appendingPathComponent(defaultModelFileName, isDirectory: true)
            if fm.fileExists(atPath: compiled.path) { return compiled }
            let package = dir.appendingPathComponent(defaultPackageFileName, isDirectory: true)
            if fm.fileExists(atPath: package.path) { return package }
        }
        if let bundled = Bundle.main.url(forResource: "EcapaLid107", withExtension: "mlmodelc") {
            return bundled
        }
        return nil
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1_000.0 + Double(components.attoseconds) / 1e15
    }

    enum IdentifierError: LocalizedError {
        case modelUnavailable
        case emptyAudio
        case audioTooShort
        case invalidModelOutput

        var errorDescription: String? {
            switch self {
            case .modelUnavailable: "Spoken language identification model is not installed."
            case .emptyAudio: "No audio samples were provided for language identification."
            case .audioTooShort: "Audio prefix is too short for language identification."
            case .invalidModelOutput: "Language identification model returned an unexpected output."
            }
        }
    }
}
