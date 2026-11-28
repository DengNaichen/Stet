@preconcurrency import AVFoundation
import Foundation
import Speech
import StetCore
#if canImport(UIKit)
    import UIKit
#endif

// MARK: - Recognition Session Seam (Enables Deterministic Simulator Tests)

nonisolated struct AppleSpeechPartialUpdate: Sendable, Equatable {
    let text: String
    let isFinal: Bool
}

nonisolated protocol AppleSpeechRecognitionSession: AnyObject, Sendable {
    var updates: AsyncThrowingStream<AppleSpeechPartialUpdate, any Error> { get }
    func start(hotwords: [String]) async throws
    func feed(samples: [Float]) throws
    func finalizeAndFinish() async throws
    func cancelAndFinishNow() async
}

nonisolated protocol AppleSpeechRecognitionBackend: Sendable {
    func makeSession(
        locale: Locale,
        backend: SpeechTranscriberBackend
    ) -> any AppleSpeechRecognitionSession
}

@MainActor
protocol MobileASREngineRoutingReporting: AnyObject {
    func routingTelemetry(for sessionId: String) -> DictationRoutingTelemetry?
}

// MARK: - Live Apple Speech Session (iOS 26 SpeechAnalyzer + .lingering)

private final class LiveAppleSpeechBackend: AppleSpeechRecognitionBackend {
    func makeSession(
        locale: Locale,
        backend: SpeechTranscriberBackend
    ) -> any AppleSpeechRecognitionSession {
        LiveAppleSpeechSession(locale: locale, backend: backend)
    }
}

private final class LiveAppleSpeechSession: AppleSpeechRecognitionSession, @unchecked Sendable {
    let updates: AsyncThrowingStream<AppleSpeechPartialUpdate, any Error>

    private enum ActiveTranscriber {
        case speech(SpeechTranscriber)
        case dictation(DictationTranscriber)
    }

    private let locale: Locale
    private let backend: SpeechTranscriberBackend
    private let updatesContinuation: AsyncThrowingStream<AppleSpeechPartialUpdate, any Error>.Continuation
    private let lock = NSLock()

    private var analyzer: SpeechAnalyzer?
    private var conversion: AudioConversion?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var didFinishInputs = false

    init(locale: Locale, backend: SpeechTranscriberBackend) {
        self.locale = locale
        self.backend = backend
        (updates, updatesContinuation) = AsyncThrowingStream.makeStream()
    }

    func start(hotwords: [String]) async throws {
        let activeTranscriber: ActiveTranscriber
        let modules: [any SpeechModule]
        switch backend {
        case .speechTranscriber:
            let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
            activeTranscriber = .speech(transcriber)
            modules = [transcriber]
        case .dictationTranscriber:
            let transcriber = DictationTranscriber(locale: locale, preset: .progressiveLongDictation)
            activeTranscriber = .dictation(transcriber)
            modules = [transcriber]
        }

        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: modules) else {
            throw AppleSpeechDictationEngine.EngineError.audioFormatUnavailable
        }
        let audioConversion = try AudioConversion(outputFormat: format)
        // `.lingering` keeps recently used locales warm inside Apple's speech service across
        // alternating zh-CN <-> en-US turns (~7-9 ms prepareToAnalyze vs ~30 ms default)
        // without holding two live SpeechAnalyzer instances concurrently.
        let options = SpeechAnalyzer.Options(priority: .userInitiated, modelRetention: .lingering)
        let speechAnalyzer = SpeechAnalyzer(modules: modules, options: options)
        // Unbounded input stream is safe because AudioSessionFIFO enforces the hard sample cap
        // and feeds chunks sequentially from a single pull cursor.
        let inputs = AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy: .unbounded)

        if case .dictation = activeTranscriber, !hotwords.isEmpty {
            let context = AnalysisContext()
            context.contextualStrings[.general] = Array(hotwords.prefix(100))
            try await speechAnalyzer.setContext(context)
        }

        do {
            try await speechAnalyzer.prepareToAnalyze(in: format)
            try await speechAnalyzer.start(inputSequence: inputs.stream)
        } catch {
            inputs.continuation.finish()
            await speechAnalyzer.cancelAndFinishNow()
            throw error
        }

        let results = Task { [updatesContinuation] in
            do {
                switch activeTranscriber {
                case .speech(let speechTranscriber):
                    for try await result in speechTranscriber.results {
                        try Task.checkCancellation()
                        updatesContinuation.yield(
                            AppleSpeechPartialUpdate(
                                text: String(result.text.characters),
                                isFinal: result.isFinal
                            )
                        )
                    }
                case .dictation(let dictationTranscriber):
                    for try await result in dictationTranscriber.results {
                        try Task.checkCancellation()
                        updatesContinuation.yield(
                            AppleSpeechPartialUpdate(
                                text: String(result.text.characters),
                                isFinal: result.isFinal
                            )
                        )
                    }
                }
                updatesContinuation.finish()
            } catch {
                if Task.isCancelled {
                    updatesContinuation.finish()
                } else {
                    updatesContinuation.finish(throwing: error)
                }
            }
        }

        lock.withLock {
            self.analyzer = speechAnalyzer
            self.conversion = audioConversion
            self.inputContinuation = inputs.continuation
            self.resultsTask = results
        }
    }

    func feed(samples: [Float]) throws {
        guard !samples.isEmpty else { return }
        let (conv, cont): (AudioConversion?, AsyncStream<AnalyzerInput>.Continuation?) = lock.withLock {
            (conversion, inputContinuation)
        }
        guard let conv, let cont else { throw CancellationError() }
        let buffer = try conv.convert(samples)
        if buffer.frameLength > 0 {
            cont.yield(AnalyzerInput(buffer: buffer))
        }
    }

    func finalizeAndFinish() async throws {
        let (conv, cont, speechAnalyzer):
            (
                AudioConversion?,
                AsyncStream<AnalyzerInput>.Continuation?,
                SpeechAnalyzer?
            ) = lock.withLock {
                guard !didFinishInputs else { return (nil, nil, analyzer) }
                didFinishInputs = true
                return (conversion, inputContinuation, analyzer)
            }

        if let conv, let cont {
            try conv.flush { buffer in
                if buffer.frameLength > 0 {
                    cont.yield(AnalyzerInput(buffer: buffer))
                }
            }
            cont.finish()
        }
        if let speechAnalyzer {
            try await speechAnalyzer.finalizeAndFinishThroughEndOfInput()
        }
    }

    func cancelAndFinishNow() async {
        let (cont, results, speechAnalyzer):
            (
                AsyncStream<AnalyzerInput>.Continuation?,
                Task<Void, Never>?,
                SpeechAnalyzer?
            ) = lock.withLock {
                let c = inputContinuation
                let r = resultsTask
                let a = analyzer
                inputContinuation = nil
                resultsTask = nil
                analyzer = nil
                conversion = nil
                didFinishInputs = true
                return (c, r, a)
            }
        cont?.finish()
        results?.cancel()
        updatesContinuation.finish()
        if let speechAnalyzer {
            await speechAnalyzer.cancelAndFinishNow()
        }
    }
}

// MARK: - Audio Conversion Helper

private struct AudioConversion {
    let sourceFormat: AVAudioFormat
    let converter: AVAudioConverter?

    init(outputFormat: AVAudioFormat) throws {
        guard
            let sourceFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: ASRAudioFrame.sampleRate,
                channels: 1,
                interleaved: false
            )
        else { throw AppleSpeechDictationEngine.EngineError.audioFormatUnavailable }
        self.sourceFormat = sourceFormat
        if sourceFormat == outputFormat {
            converter = nil
        } else {
            guard let converter = AVAudioConverter(from: sourceFormat, to: outputFormat) else {
                throw AppleSpeechDictationEngine.EngineError.audioFormatUnavailable
            }
            self.converter = converter
        }
    }

    func convert(_ samples: [Float]) throws -> AVAudioPCMBuffer {
        let frameCount = AVAudioFrameCount(samples.count)
        guard let source = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: frameCount),
            let channel = source.floatChannelData?[0]
        else { throw AppleSpeechDictationEngine.EngineError.audioConversionFailed }
        samples.withUnsafeBufferPointer { pointer in
            if let address = pointer.baseAddress {
                channel.update(from: address, count: pointer.count)
            }
        }
        source.frameLength = frameCount

        guard let converter else { return source }
        let ratio = converter.outputFormat.sampleRate / sourceFormat.sampleRate
        let capacity = AVAudioFrameCount(ceil(Double(frameCount) * ratio)) + 16
        let output = try makeOutput(for: converter, capacity: capacity)
        var suppliedInput = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if suppliedInput {
                inputStatus.pointee = .noDataNow
                return nil
            }
            suppliedInput = true
            inputStatus.pointee = .haveData
            return source
        }
        guard status != .error else { throw error ?? AppleSpeechDictationEngine.EngineError.audioConversionFailed }
        return output
    }

    func flush(_ consume: (AVAudioPCMBuffer) throws -> Void) throws {
        guard let converter else { return }
        while true {
            let output = try makeOutput(for: converter, capacity: 4096)
            var error: NSError?
            let status = converter.convert(to: output, error: &error) { _, inputStatus in
                inputStatus.pointee = .endOfStream
                return nil
            }
            guard status != .error else { throw error ?? AppleSpeechDictationEngine.EngineError.audioConversionFailed }
            try consume(output)
            guard status == .haveData, output.frameLength > 0 else { return }
        }
    }

    private func makeOutput(for converter: AVAudioConverter, capacity: AVAudioFrameCount) throws -> AVAudioPCMBuffer {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: capacity) else {
            throw AppleSpeechDictationEngine.EngineError.audioConversionFailed
        }
        return buffer
    }
}

// MARK: - Apple Speech Dictation Engine with Optional Core ML Auto-LID

@MainActor
final class AppleSpeechDictationEngine:
    @MainActor ASREngine,
    MobileASREngineFailureReporting,
    MobileASREngineRoutingReporting
{
    struct Configuration: Sendable {
        let routingPolicy: LanguageRoutingPolicy
        let maxUnconsumedSamples: Int
        let firstFrameTimeout: Duration
        let lidStopBudget: Duration
        let analyzerStartTimeout: Duration
        let volumeThrottleInterval: Duration

        static let `default` = Configuration(
            routingPolicy: .default,
            maxUnconsumedSamples: Int(ASRAudioFrame.sampleRate) * 15,
            firstFrameTimeout: .seconds(5),
            lidStopBudget: .milliseconds(400),
            analyzerStartTimeout: .seconds(8),
            volumeThrottleInterval: .milliseconds(40)
        )
    }

    let name = "Apple Speech"
    let resultStream: AsyncStream<ASRResult>
    let failureStream: AsyncStream<MobileASREngineFailure>
    var onVolumeUpdate: ((Float) -> Void)?

    private let settingsStore: SpeechRecognitionSettingsStore
    private let dictionaryModel: DictionaryModel
    private let audioCapture: any ASRAudioCapturing
    private let recognitionBackend: any AppleSpeechRecognitionBackend
    private let languageIdentifier: any SpokenLanguageIdentifying
    private let activityDetector: SpeechPrefixActivityDetector
    private let configuration: Configuration
    private let routingTargetsResolver:
        (@MainActor (Bool) async throws -> SpeechRecognitionSettingsStore.PreparedRoutingTargets)?

    private let resultContinuation: AsyncStream<ASRResult>.Continuation
    private let failureContinuation: AsyncStream<MobileASREngineFailure>.Continuation
    private var volumeRelay: ThrottledVolumeRelay?

    private var recording: Recording?
    private var previousCleanupTask: Task<Void, Never>?
    private var isStarting = false
    private var startupCancelled = false
    private var isTornDown = false
    private var lastTelemetryBySession: [String: DictationRoutingTelemetry] = [:]
    private var memoryWarningObserver: NSObjectProtocol?

    init(
        settingsStore: SpeechRecognitionSettingsStore,
        dictionaryModel: DictionaryModel = DictionaryModel(),
        audioCapture: (any ASRAudioCapturing)? = nil,
        recognitionBackend: (any AppleSpeechRecognitionBackend)? = nil,
        languageIdentifier: (any SpokenLanguageIdentifying)? = nil,
        activityDetector: SpeechPrefixActivityDetector = SpeechPrefixActivityDetector(),
        configuration: Configuration = .default,
        routingTargetsResolver: (
            @MainActor (Bool) async throws -> SpeechRecognitionSettingsStore.PreparedRoutingTargets
        )? = nil
    ) {
        self.settingsStore = settingsStore
        self.dictionaryModel = dictionaryModel
        self.audioCapture = audioCapture ?? PersistentASRAudioCapture(strategy: .builtInPreferred)
        self.recognitionBackend = recognitionBackend ?? LiveAppleSpeechBackend()
        self.languageIdentifier = languageIdentifier ?? CoreMLSpokenLanguageIdentifier()
        self.activityDetector = activityDetector
        self.configuration = configuration
        self.routingTargetsResolver = routingTargetsResolver
        (resultStream, resultContinuation) = AsyncStream.makeStream()
        (failureStream, failureContinuation) = AsyncStream.makeStream()

        self.volumeRelay = ThrottledVolumeRelay(interval: configuration.volumeThrottleInterval) { [weak self] level in
            Task { @MainActor [weak self] in
                self?.onVolumeUpdate?(level)
            }
        }

        #if canImport(UIKit)
            memoryWarningObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.didReceiveMemoryWarningNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleMemoryWarning()
                }
            }
        #endif
    }

    deinit {
        if let memoryWarningObserver {
            NotificationCenter.default.removeObserver(memoryWarningObserver)
        }
    }

    func routingTelemetry(for sessionId: String) -> DictationRoutingTelemetry? {
        lastTelemetryBySession[sessionId]
    }

    func prepare() async throws {
        try checkOpen()
        let targets = try await resolveTargets(allowSecondaryDownload: true)
        try checkOpen()
        if targets.secondary != nil {
            // Single coalesced async preload on `.cpuOnly`; non-fatal if model is missing.
            Task.detached(priority: .utility) { [languageIdentifier] in
                await languageIdentifier.preload()
            }
        } else {
            languageIdentifier.unload()
        }
        try await audioCapture.prepare()
    }

    func start(sessionId: String) async throws {
        try checkOpen()
        guard !isStarting, recording?.isStopping != false else {
            throw ASRAudioCaptureError.consumerAlreadyActive
        }
        discardRecording()
        isStarting = true
        startupCancelled = false
        defer { isStarting = false }

        // Freeze backend + primary/secondary targets for this session without blocking on secondary downloads.
        let targets = try await resolveTargets(allowSecondaryDownload: false)
        try checkStartup()

        let token = UUID()
        let fifo = AudioSessionFIFO(
            maxUnconsumedSamples: configuration.maxUnconsumedSamples,
            maxPrefixRetainedSamples: Int(
                (configuration.routingPolicy.maxLIDWindowSeconds + 1.0) * ASRAudioFrame.sampleRate
            )
        )
        let startedAt = ProcessInfo.processInfo.systemUptime
        let hotwords: [String] =
            if targets.backend == .dictationTranscriber, dictionaryModel.loadIsEnabled() {
                Array(dictionaryModel.loadEntries().prefix(100))
            } else {
                []
            }

        volumeRelay?.beginSession(generation: token)

        do {
            // Open the capture gate immediately so opening speech is captured into this session's
            // FIFO while LID and/or SpeechAnalyzer prepare runs asynchronously.
            try await audioCapture.start { [weak self, fifo, token] result in
                switch result {
                case .success(let frame):
                    guard !frame.samples.isEmpty else { return }
                    self?.volumeRelay?.publish(frame.level, generation: token)
                    _ = fifo.append(frame.samples)
                case .failure(let error):
                    fifo.abort(with: error)
                }
            }
            try checkStartup()
        } catch {
            volumeRelay?.endSession(generation: token)
            audioCapture.stop()
            fifo.abort(with: error)
            throw error
        }

        let pipelineTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.runSessionPipeline(
                sessionId: sessionId,
                token: token,
                startedAt: startedAt,
                targets: targets,
                hotwords: hotwords,
                fifo: fifo
            )
        }

        recording = Recording(
            id: sessionId,
            token: token,
            fifo: fifo,
            pipelineTask: pipelineTask
        )
    }

    /// Normal user stop: closes capture gate, freezes FIFO terminal offset, and lets the pipeline
    /// settle (including short-utterance LID if enough speech was captured) and emit one final result.
    func stop() {
        if isStarting { startupCancelled = true }
        guard let recording, !recording.isStopping else { return }
        self.recording?.isStopping = true
        volumeRelay?.endSession(generation: recording.token)
        audioCapture.stop()
        recording.fifo.sealEnd()
    }

    /// Immediate cancellation/abandon: invalidates session token, stops capture, aborts FIFO and
    /// in-flight LID/analyzer work without emitting any final result.
    func cancel() {
        if isStarting { startupCancelled = true }
        discardRecording()
    }

    func resetAudio() async throws {
        try checkOpen()
        if isStarting { startupCancelled = true }
        if let recording {
            failRecording(token: recording.token, error: EngineError.audioReset)
        }
        try await audioCapture.reset()
    }

    func teardown() {
        guard !isTornDown else { return }
        isTornDown = true
        discardRecording()
        volumeRelay?.stopAll()
        languageIdentifier.unload()
        audioCapture.teardown()
        resultContinuation.finish()
        failureContinuation.finish()
    }

    // MARK: - Session Pipeline

    private func runSessionPipeline(
        sessionId: String,
        token: UUID,
        startedAt: TimeInterval,
        targets: SpeechRecognitionSettingsStore.PreparedRoutingTargets,
        hotwords: [String],
        fifo: AudioSessionFIFO
    ) async {
        do {
            // 1. Wait for first audio frame with a watchdog starting at capture-gate open.
            let firstSnapshot = try await waitForFirstFrame(fifo: fifo)
            try checkActive(token: token)

            if firstSnapshot.isSealed, firstSnapshot.totalReceivedSamples == 0 {
                let telemetry = DictationRoutingTelemetry(
                    routedLanguageCode: targets.primary.language.localeIdentifier,
                    routingReason: .insufficientSpeechFallback,
                    lidMs: nil,
                    analyzerPrepareMs: nil
                )
                complete(
                    token: token,
                    text: "",
                    metrics: ASRMetrics(
                        audioDuration: 0,
                        cpuDuration: 0,
                        wallDuration: ProcessInfo.processInfo.systemUptime - startedAt,
                        rtf: 0
                    ),
                    telemetry: telemetry
                )
                return
            }

            // 2. Decide target language (single-language bypass or Core ML prefix LID).
            let routeOutcome = try await decideTarget(
                token: token,
                targets: targets,
                fifo: fifo
            )
            fifo.releasePrefixRetention()
            try checkActive(token: token)

            // 3. Serialize teardown of any prior SpeechAnalyzer before creating the next one
            // so we never overlap incompatible analyzer instances on iOS.
            if let pendingCleanup = previousCleanupTask {
                await pendingCleanup.value
                try checkActive(token: token)
            }

            // 4. Create and start the chosen locale's recognition session with a real timeout.
            let speechSession = recognitionBackend.makeSession(
                locale: routeOutcome.target.locale,
                backend: targets.backend
            )
            attachSession(speechSession, to: token)

            let prepareStartedAt = ContinuousClock.now
            try await startSpeechSessionWithTimeout(
                speechSession,
                hotwords: hotwords,
                timeout: configuration.analyzerStartTimeout
            )
            let prepareMs = Self.elapsedMilliseconds(since: prepareStartedAt)
            try checkActive(token: token)

            // 5. Consume partial/final updates concurrently while draining FIFO via one cursor.
            let resultsTask = Task<String, any Error> { [weak self] in
                var finalizedText = ""
                for try await update in speechSession.updates {
                    try Task.checkCancellation()
                    let isActive = await MainActor.run { self?.recording?.token == token }
                    guard isActive else { throw CancellationError() }
                    if update.isFinal {
                        finalizedText += update.text
                    }
                    let displayed = update.isFinal ? finalizedText : finalizedText + update.text
                    await MainActor.run { [weak self] in
                        guard let self, self.recording?.token == token else { return }
                        self.resultContinuation.yield(
                            ASRResult(sessionId: sessionId, text: displayed, isFinal: false)
                        )
                    }
                }
                let endedWhileRecording = await MainActor.run {
                    self?.recording?.token == token && self?.recording?.isStopping == false
                }
                if endedWhileRecording, !Task.isCancelled {
                    throw EngineError.analysisEnded
                }
                return finalizedText.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            attachResultsTask(resultsTask, to: token)

            // 6. Drain buffered prefix + live audio from one shared cursor in sequential chunks.
            var totalFedSamples = 0
            while let chunk = try await fifo.nextChunk(maxSamples: 3_200) {
                try Task.checkCancellation()
                try checkActive(token: token)
                guard !chunk.isEmpty else { continue }
                totalFedSamples += chunk.count
                try speechSession.feed(samples: chunk)
            }
            try Task.checkCancellation()
            try checkActive(token: token)

            let text: String
            if totalFedSamples > 0 {
                try await speechSession.finalizeAndFinish()
                text = try await resultsTask.value
            } else {
                resultsTask.cancel()
                await speechSession.cancelAndFinishNow()
                text = ""
            }
            try checkActive(token: token)

            let duration = Double(totalFedSamples) / ASRAudioFrame.sampleRate
            let wallDuration = ProcessInfo.processInfo.systemUptime - startedAt
            let telemetry = DictationRoutingTelemetry(
                routedLanguageCode: routeOutcome.target.language.localeIdentifier,
                routingReason: routeOutcome.reason,
                lidMs: routeOutcome.lidMs,
                analyzerPrepareMs: prepareMs
            )
            complete(
                token: token,
                text: text,
                metrics: ASRMetrics(
                    audioDuration: duration,
                    cpuDuration: 0,
                    wallDuration: wallDuration,
                    rtf: duration > 0 ? wallDuration / duration : 0
                ),
                telemetry: telemetry
            )
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            failRecording(token: token, error: error)
        }
    }

    private struct RouteOutcome {
        let target: SpeechRecognitionSettingsStore.PreparedSpeechTarget
        let reason: LanguageRoutingReason
        let lidMs: Int?
    }

    private func decideTarget(
        token: UUID,
        targets: SpeechRecognitionSettingsStore.PreparedRoutingTargets,
        fifo: AudioSessionFIFO
    ) async throws -> RouteOutcome {
        guard let secondary = targets.secondary else {
            return RouteOutcome(target: targets.primary, reason: .singleLanguageBypass, lidMs: nil)
        }
        guard targets.primary.language.voxLinguaCode != secondary.language.voxLinguaCode else {
            return RouteOutcome(target: targets.primary, reason: .sameIdentifierBypass, lidMs: nil)
        }
        guard languageIdentifier.isModelAvailable else {
            return RouteOutcome(target: targets.primary, reason: .lidUnavailableFallback, lidMs: nil)
        }

        let policy = configuration.routingPolicy
        let maxWindowSamples = Int(policy.maxLIDWindowSeconds * ASRAudioFrame.sampleRate)
        let deadline = ContinuousClock.now + .seconds(policy.wallClockDeadlineSeconds)
        var didAttemptEarlyLock = false
        var lastLIDMs: Int?

        while true {
            try Task.checkCancellation()
            try checkActive(token: token)

            let snapshot = fifo.currentPrefixSnapshot()
            let (window, activity) = activityDetector.extractLIDWindow(
                from: snapshot.samples,
                maxWindowSamples: maxWindowSamples
            )

            let reachedStandardWindow = activity.activeSpeechSeconds >= policy.standardLockSpeechSeconds
            let reachedWallClock = ContinuousClock.now >= deadline
            let isFinalAttempt = snapshot.isSealed || reachedStandardWindow || reachedWallClock

            if isFinalAttempt {
                if activity.activeSpeechSeconds < policy.minActiveSpeechForDecision {
                    let reason: LanguageRoutingReason =
                        reachedWallClock && !snapshot.isSealed
                        ? .wallClockDeadlineFallback
                        : .insufficientSpeechFallback
                    return RouteOutcome(target: targets.primary, reason: reason, lidMs: lastLIDMs)
                }

                do {
                    let scores = try await runLIDWithBudget(
                        samples: window,
                        budget: snapshot.isSealed ? configuration.lidStopBudget : .seconds(1)
                    )
                    let lidMs = Int(scores.totalInferenceMs.rounded())
                    lastLIDMs = lidMs
                    let decision = policy.evaluate(
                        primary: targets.primary.language,
                        secondary: secondary.language,
                        scores: scores,
                        activeSpeechSeconds: activity.activeSpeechSeconds,
                        isFinalWindow: true
                    )
                    let chosenTarget =
                        decision?.selectedLanguage == secondary.language ? secondary : targets.primary
                    return RouteOutcome(
                        target: chosenTarget,
                        reason: decision?.reason ?? .finalPrimary,
                        lidMs: lidMs
                    )
                } catch is CancellationError {
                    throw CancellationError()
                } catch EngineError.lidTimedOut {
                    return RouteOutcome(target: targets.primary, reason: .lidTimeoutFallback, lidMs: lastLIDMs)
                } catch {
                    return RouteOutcome(target: targets.primary, reason: .lidFailedFallback, lidMs: lastLIDMs)
                }
            }

            if !didAttemptEarlyLock, activity.activeSpeechSeconds >= policy.earlyLockSpeechSeconds {
                didAttemptEarlyLock = true
                do {
                    let scores = try await languageIdentifier.identify(samples: window)
                    let lidMs = Int(scores.totalInferenceMs.rounded())
                    lastLIDMs = lidMs
                    if let earlyDecision = policy.evaluate(
                        primary: targets.primary.language,
                        secondary: secondary.language,
                        scores: scores,
                        activeSpeechSeconds: activity.activeSpeechSeconds,
                        isFinalWindow: false
                    ) {
                        let chosenTarget =
                            earlyDecision.selectedLanguage == secondary.language ? secondary : targets.primary
                        return RouteOutcome(
                            target: chosenTarget,
                            reason: earlyDecision.reason,
                            lidMs: lidMs
                        )
                    }
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    return RouteOutcome(target: targets.primary, reason: .lidFailedFallback, lidMs: lastLIDMs)
                }
            }

            // Wait for more audio (~150 ms increment) or remaining wall-clock budget / seal.
            let nextSampleGoal = snapshot.totalReceivedSamples + Int(0.15 * ASRAudioFrame.sampleRate)
            let remaining = deadline - ContinuousClock.now
            guard remaining > .zero else { continue }
            _ = try? await waitForPrefixOrTimeout(
                fifo: fifo,
                minSamples: nextSampleGoal,
                timeout: min(remaining, .milliseconds(200))
            )
        }
    }

    private func waitForFirstFrame(fifo: AudioSessionFIFO) async throws -> AudioSessionFIFO.Snapshot {
        let timeout = configuration.firstFrameTimeout
        return try await withThrowingTaskGroup(of: AudioSessionFIFO.Snapshot.self) { group in
            group.addTask {
                try await fifo.waitForPrefix(minSamples: 1)
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw EngineError.noAudioFrames
            }
            guard let first = try await group.next() else {
                throw CancellationError()
            }
            group.cancelAll()
            return first
        }
    }

    private func waitForPrefixOrTimeout(
        fifo: AudioSessionFIFO,
        minSamples: Int,
        timeout: Duration
    ) async throws -> AudioSessionFIFO.Snapshot? {
        try await withThrowingTaskGroup(of: AudioSessionFIFO.Snapshot?.self) { group in
            group.addTask {
                try await fifo.waitForPrefix(minSamples: minSamples)
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                return nil
            }
            let result = try await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }

    private func runLIDWithBudget(
        samples: [Float],
        budget: Duration
    ) async throws -> SpokenLanguageScores {
        try await withThrowingTaskGroup(of: SpokenLanguageScores.self) { group in
            group.addTask { [languageIdentifier] in
                try await languageIdentifier.identify(samples: samples)
            }
            group.addTask {
                try await Task.sleep(for: budget)
                throw EngineError.lidTimedOut
            }
            guard let result = try await group.next() else {
                throw CancellationError()
            }
            group.cancelAll()
            return result
        }
    }

    private func startSpeechSessionWithTimeout(
        _ session: any AppleSpeechRecognitionSession,
        hotwords: [String],
        timeout: Duration
    ) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await session.start(hotwords: hotwords)
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw EngineError.analyzerStartTimedOut
            }
            do {
                try await group.next()
                group.cancelAll()
            } catch {
                group.cancelAll()
                await session.cancelAndFinishNow()
                throw error
            }
        }
    }

    // MARK: - Helpers & Lifecycle

    private func resolveTargets(
        allowSecondaryDownload: Bool
    ) async throws -> SpeechRecognitionSettingsStore.PreparedRoutingTargets {
        if let routingTargetsResolver {
            return try await routingTargetsResolver(allowSecondaryDownload)
        }
        return try await settingsStore.prepareRoutingTargets(allowSecondaryDownload: allowSecondaryDownload)
    }

    private func checkOpen() throws {
        try Task.checkCancellation()
        guard !isTornDown else { throw CancellationError() }
    }

    private func checkStartup() throws {
        try checkOpen()
        guard !startupCancelled else { throw CancellationError() }
    }

    private func checkActive(token: UUID) throws {
        try checkOpen()
        guard recording?.token == token else { throw CancellationError() }
    }

    private func attachSession(_ session: any AppleSpeechRecognitionSession, to token: UUID) {
        guard recording?.token == token else { return }
        recording?.session = session
    }

    private func attachResultsTask(_ task: Task<String, any Error>, to token: UUID) {
        guard recording?.token == token else { return }
        recording?.resultsTask = task
    }

    private func complete(
        token: UUID,
        text: String,
        metrics: ASRMetrics,
        telemetry: DictationRoutingTelemetry
    ) {
        guard let recording, recording.token == token else { return }
        self.recording = nil
        volumeRelay?.endSession(generation: token)
        lastTelemetryBySession[recording.id] = telemetry
        if lastTelemetryBySession.count > 16 {
            lastTelemetryBySession = [recording.id: telemetry]
        }
        resultContinuation.yield(
            ASRResult(sessionId: recording.id, text: text, isFinal: true, metrics: metrics)
        )
    }

    private func failRecording(token: UUID, error: any Error) {
        guard let recording, recording.token == token else { return }
        let sessionId = recording.id
        discardRecording()
        failureContinuation.yield(
            MobileASREngineFailure(sessionId: sessionId, message: error.localizedDescription)
        )
    }

    private func discardRecording() {
        guard let recording else { return }
        self.recording = nil
        volumeRelay?.endSession(generation: recording.token)
        audioCapture.stop()
        recording.fifo.abort(with: CancellationError())
        recording.resultsTask?.cancel()
        recording.pipelineTask.cancel()
        if let session = recording.session {
            let priorCleanup = previousCleanupTask
            previousCleanupTask = Task {
                await priorCleanup?.value
                await session.cancelAndFinishNow()
            }
        }
    }

    private func handleMemoryWarning() {
        guard recording == nil else { return }
        languageIdentifier.unload()
        Task {
            await SpeechModels.endRetention()
        }
    }

    private static func elapsedMilliseconds(since startedAt: ContinuousClock.Instant) -> Int {
        let components = (ContinuousClock.now - startedAt).components
        let ms = Double(components.seconds) * 1_000.0 + Double(components.attoseconds) / 1e15
        return max(0, Int(ms.rounded()))
    }

    private struct Recording {
        let id: String
        let token: UUID
        let fifo: AudioSessionFIFO
        let pipelineTask: Task<Void, Never>
        var session: (any AppleSpeechRecognitionSession)?
        var resultsTask: Task<String, any Error>?
        var isStopping = false
    }

    enum EngineError: LocalizedError, Equatable {
        case audioFormatUnavailable
        case audioConversionFailed
        case audioBacklog
        case audioReset
        case analysisEnded
        case noAudioFrames
        case lidTimedOut
        case analyzerStartTimedOut

        var errorDescription: String? {
            switch self {
            case .audioFormatUnavailable: "Apple Speech could not find a compatible audio format."
            case .audioConversionFailed: "Microphone audio could not be converted for Apple Speech."
            case .audioBacklog: "Apple Speech could not keep up with the microphone."
            case .audioReset: "Audio services were reset. Please try again."
            case .analysisEnded: "Apple Speech ended before the recording was stopped."
            case .noAudioFrames: "No microphone audio arrived. Please try again."
            case .lidTimedOut: "Language detection timed out."
            case .analyzerStartTimedOut: "Apple Speech took too long to start. Please try again."
            }
        }
    }
}
