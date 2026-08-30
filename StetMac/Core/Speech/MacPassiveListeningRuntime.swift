#if os(macOS)
    @preconcurrency import AVFoundation
    import Foundation
    import StetASR
    import StetCore

    enum MacPassiveListeningRuntimeError: LocalizedError {
        case ownerProfileUnavailable

        var errorDescription: String? {
            switch self {
            case .ownerProfileUnavailable:
                return "Enroll an owner voice profile to enable passive listening."
            }
        }
    }

    nonisolated enum MacPassiveListeningRestartRequest: Equatable, Sendable {
        case start
        case coalesced
        case deferred
    }

    nonisolated struct MacPassiveListeningRestartGate {
        private(set) var isActiveCaptureInProgress = false
        private(set) var isRestartInFlight = false
        private var hasDeferredRestart = false

        mutating func beginActiveCapture() {
            isActiveCaptureInProgress = true
        }

        mutating func requestRestart() -> MacPassiveListeningRestartRequest {
            guard !isActiveCaptureInProgress else {
                hasDeferredRestart = true
                return .deferred
            }
            guard !isRestartInFlight else { return .coalesced }
            isRestartInFlight = true
            return .start
        }

        mutating func finishRestart() {
            isRestartInFlight = false
        }

        mutating func finishActiveCapture() -> Bool {
            isActiveCaptureInProgress = false
            defer { hasDeferredRestart = false }
            return hasDeferredRestart
        }

        mutating func reset() {
            isActiveCaptureInProgress = false
            isRestartInFlight = false
            hasDeferredRestart = false
        }
    }

    private nonisolated enum MacPassiveListeningLifecycleOperation: Equatable, Sendable {
        case start
        case stop
        case restart
    }

    private actor MacPassiveAnalysisRuntime {
        let analyzer: FluidAudioPassiveSpeechAnalyzer
        private var speechIsActive = false

        init(analyzer: FluidAudioPassiveSpeechAnalyzer) {
            self.analyzer = analyzer
        }

        func detect(_ samples: [Float]) async throws -> PassiveSpeechActivity {
            let observations = try await analyzer.processVoiceActivity(samples)
            var didSpeechEnd = false
            for observation in observations {
                speechIsActive = observation.isSpeechActive
                if case .speechEnded = observation.event {
                    didSpeechEnd = true
                }
            }
            return PassiveSpeechActivity(
                isSpeechActive: speechIsActive,
                didSpeechEnd: didSpeechEnd
            )
        }

        func resetAll() async {
            speechIsActive = false
            await analyzer.resetVoiceActivity()
            await analyzer.resetAcceptedAudio()
        }

        func resetDiarization() async {
            await analyzer.resetAcceptedAudio()
        }

        func addDiarizedAudio(_ samples: [Float]) async throws -> [PassiveDiarizedRegion] {
            try await analyzer.addAcceptedAudio(samples)
        }

        func finalizeDiarizedAudio() async throws -> [PassiveDiarizedRegion] {
            try await analyzer.finalizeAcceptedAudio()
        }
    }

    private actor MacPassiveSpeakerIdentityRuntime {
        private let profileStore: SpeakerProfileStore
        private let modelManager: SpeakerEmbeddingModelManager

        init(
            profileStore: SpeakerProfileStore,
            modelManager: SpeakerEmbeddingModelManager
        ) {
            self.profileStore = profileStore
            self.modelManager = modelManager
        }

        func prepare() async throws {
            let profiles = try await profileStore.loadProfiles()
            guard profiles.contains(where: { $0.role == .owner && $0.status == .ready }) else {
                throw MacPassiveListeningRuntimeError.ownerProfileUnavailable
            }
            let recognizer = try await modelManager.recognizer()
            let currentProfiles = try await profileStore.loadProfiles(currentModel: recognizer.model)
            guard currentProfiles.contains(where: { $0.role == .owner && $0.status == .ready }) else {
                throw MacPassiveListeningRuntimeError.ownerProfileUnavailable
            }
        }

        func verifyOwner(_ samples: [Float]) async throws -> PassiveSpeakerMatch {
            let recognizer = try await modelManager.recognizer()
            let profiles = try await profileStore.loadProfiles(currentModel: recognizer.model)
            guard let owner = profiles.first(where: { $0.role == .owner && $0.status == .ready }) else {
                return PassiveSpeakerMatch(identity: .other, similarity: nil)
            }
            return try await match(
                samples,
                profiles: [owner],
                recognizer: recognizer,
                runnerUpMargin: 0
            )
        }

        func identify(_ samples: [Float]) async throws -> PassiveSpeakerMatch {
            let recognizer = try await modelManager.recognizer()
            let profiles = try await profileStore.loadProfiles(currentModel: recognizer.model)
                .filter { $0.status == .ready }
            return try await match(
                samples,
                profiles: profiles,
                recognizer: recognizer,
                runnerUpMargin: 0.08
            )
        }

        private func match(
            _ samples: [Float],
            profiles: [SpeakerProfile],
            recognizer: SpeakerEmbeddingRecognizer,
            runnerUpMargin: Double
        ) async throws -> PassiveSpeakerMatch {
            let embedding: [Float]
            do {
                embedding = try await recognizer.extractEmbedding(from: samples)
            } catch SpeakerEmbeddingRecognizerError.invalidEmbedding {
                return PassiveSpeakerMatch(identity: .unresolved, similarity: nil)
            }
            let decision = try SpeakerEmbeddingRecognizer.match(
                embedding: embedding,
                voicedSampleCount: samples.count,
                sampleRate: MacPassiveListeningConfiguration.sampleRate,
                profiles: profiles.map {
                    SpeakerEmbeddingProfileReference(
                        id: $0.id,
                        model: $0.model,
                        normalizedCentroid: $0.normalizedCentroid,
                        matchThreshold: $0.matchThreshold
                    )
                },
                model: recognizer.model,
                runnerUpMargin: runnerUpMargin
            )
            switch decision {
            case .matched(let profileID, let similarity):
                guard let profile = profiles.first(where: { $0.id == profileID }) else {
                    return PassiveSpeakerMatch(identity: .unresolved, similarity: similarity)
                }
                let identity: CapturedSpeakerIdentity =
                    profile.role == .owner
                    ? .self
                    : .known(profileID: profile.id, displayName: profile.displayName)
                return PassiveSpeakerMatch(identity: identity, similarity: similarity)
            case .other(let similarity):
                return PassiveSpeakerMatch(identity: .other, similarity: similarity)
            case .unresolved:
                return PassiveSpeakerMatch(identity: .unresolved, similarity: nil)
            }
        }
    }

    extension MacPassiveListeningCoordinator {
        nonisolated static func live(
            profileStore: SpeakerProfileStore = SpeakerProfileStore(),
            modelManager: SpeakerEmbeddingModelManager = SpeakerEmbeddingModelManager()
        ) async throws -> MacPassiveListeningCoordinator {
            let identity = MacPassiveSpeakerIdentityRuntime(
                profileStore: profileStore,
                modelManager: modelManager
            )
            try await identity.prepare()

            let analysis = MacPassiveAnalysisRuntime(
                analyzer: try await FluidAudioPassiveSpeechAnalyzer.load()
            )
            let nano = try await MainActor.run { try FunASRNanoTranscriptionService() }
            let history = await MainActor.run { DictationHistoryService.shared }
            return MacPassiveListeningCoordinator(
                dependencies: MacPassiveListeningDependencies(
                    detectVoiceActivity: { try await analysis.detect($0) },
                    verifyOwner: { try await identity.verifyOwner($0) },
                    addDiarizedAudio: { try await analysis.addDiarizedAudio($0) },
                    finalizeDiarizedAudio: { try await analysis.finalizeDiarizedAudio() },
                    resetAnalysis: { await analysis.resetAll() },
                    resetDiarization: { await analysis.resetDiarization() },
                    identifySpeaker: { try await identity.identify($0) },
                    transcribeAudioFile: { url in
                        try await nano.transcribe(
                            audioFileAt: url,
                            languageCode: nil,
                            prompt: nil,
                            audioDurationSeconds: nil
                        ).text
                    },
                    historyCreate: { id, startedAt in
                        try await MainActor.run {
                            _ = try history.createPassiveCapture(id: id, startedAt: startedAt)
                        }
                    },
                    historyUpdate: { id, text, regions in
                        try await MainActor.run {
                            try history.updatePassiveCapture(
                                id: id,
                                rawText: text,
                                speakerRegions: regions
                            )
                        }
                    },
                    historyFinish: { id, endedAt, text, regions in
                        try await MainActor.run {
                            try history.finishPassiveCapture(
                                id: id,
                                endedAt: endedAt,
                                rawText: text,
                                speakerRegions: regions
                            )
                        }
                    },
                    historyFail: { id, endedAt, code, text, regions in
                        try await MainActor.run {
                            try history.failPassiveCapture(
                                id: id,
                                endedAt: endedAt,
                                failureCode: code,
                                retainedText: text,
                                speakerRegions: regions
                            )
                        }
                    }
                )
            )
        }
    }

    actor MacPassiveListeningRuntime {
        typealias StateHandler = @MainActor @Sendable (MacPassiveListeningState) -> Void

        private let captureService: MacAudioCaptureService
        private let makeCoordinator: @Sendable () async throws -> MacPassiveListeningCoordinator
        private var stateHandler: StateHandler
        private var coordinator: MacPassiveListeningCoordinator?
        private var frameTask: Task<Void, Never>?
        private var captureLiveness = MacPassiveCaptureLivenessMonitor()
        private var captureLivenessTask: Task<Void, Never>?
        private var restartGate = MacPassiveListeningRestartGate()
        private var isEnabled = true
        private var lifecycleTask: Task<Void, Never>?
        private var lifecycleOperation: MacPassiveListeningLifecycleOperation?
        private var lifecycleGeneration = 0

        init(
            captureService: MacAudioCaptureService,
            makeCoordinator: @escaping @Sendable () async throws -> MacPassiveListeningCoordinator = {
                try await MacPassiveListeningCoordinator.live()
            },
            stateHandler: @escaping StateHandler = { _ in }
        ) {
            self.captureService = captureService
            self.makeCoordinator = makeCoordinator
            self.stateHandler = stateHandler
        }

        func setStateHandler(_ handler: @escaping StateHandler) {
            stateHandler = handler
        }

        func start() async {
            guard isEnabled else { return }
            await lifecycleTask(for: .start).value
        }

        func setEnabled(_ enabled: Bool) async {
            isEnabled = enabled
            guard !restartGate.isActiveCaptureInProgress else { return }

            if enabled {
                await lifecycleTask(for: .start).value
            } else {
                await lifecycleTask(for: .stop).value
                guard !isEnabled else { return }
                await stateHandler(.unavailable("Passive listening is off"))
            }
        }

        private func startRuntime() async {
            guard frameTask == nil else { return }
            guard isEnabled, !restartGate.isActiveCaptureInProgress else { return }
            guard AVAudioApplication.shared.recordPermission == .granted else {
                await stateHandler(.unavailable("Microphone permission is not granted"))
                return
            }
            await stateHandler(.unavailable("Waiting for microphone audio"))
            MacPassiveListeningCoordinator.cleanupOrphanedTemporaryAudio()
            do {
                let coordinator = try await makeCoordinator()
                guard isEnabled, !restartGate.isActiveCaptureInProgress else { return }
                let stream = await captureService.makeAudioCaptureFrameStream()
                let captureStartSample = await captureService.currentAudioCaptureSamplePosition()
                try await captureService.startContinuousCapture()
                guard isEnabled, !restartGate.isActiveCaptureInProgress else {
                    await captureService.stopContinuousCapture()
                    return
                }
                _ = await captureService.beginNextAudioCaptureEpoch()
                let epoch = await captureService.currentAudioCaptureEpoch()
                await coordinator.arm(epoch: epoch)
                self.coordinator = coordinator
                captureLiveness.start(
                    at: ProcessInfo.processInfo.systemUptime,
                    samplePosition: captureStartSample
                )
                frameTask = Task { [weak self] in
                    for await frame in stream {
                        guard !Task.isCancelled else { break }
                        await self?.ingest(frame, with: coordinator)
                    }
                }
                startCaptureLivenessWatchdog()
            } catch {
                coordinator = nil
                await stateHandler(.unavailable(error.localizedDescription))
            }
        }

        func restart() async {
            guard isEnabled else { return }
            switch restartGate.requestRestart() {
            case .start:
                await lifecycleTask(for: .restart).value
            case .coalesced:
                await waitForLifecycleDrain()
            case .deferred:
                return
            }
        }

        func revalidatePermission() async {
            guard isEnabled else {
                await stateHandler(.unavailable("Passive listening is off"))
                return
            }
            if AVAudioApplication.shared.recordPermission == .granted {
                if frameTask == nil {
                    await start()
                }
            } else {
                guard !restartGate.isActiveCaptureInProgress else { return }
                if let coordinator {
                    await coordinator.setUnavailable("Microphone permission is not granted")
                }
                await lifecycleTask(for: .stop).value
                await stateHandler(.unavailable("Microphone permission is not granted"))
            }
        }

        func beginActive() async {
            await waitForLifecycleDrain()
            restartGate.beginActiveCapture()
            guard let coordinator else {
                await stateHandler(.active)
                return
            }
            _ = await captureService.beginNextAudioCaptureEpoch()
            let epoch = await captureService.currentAudioCaptureEpoch()
            await coordinator.hotkeyDown(newEpoch: epoch)
            await stateHandler(.active)
        }

        func resumePassive() async {
            if isEnabled, AVAudioApplication.shared.recordPermission == .granted, let coordinator {
                _ = await captureService.beginNextAudioCaptureEpoch()
                let epoch = await captureService.currentAudioCaptureEpoch()
                await coordinator.hotkeyUp(newEpoch: epoch)
            }

            let shouldRestart = restartGate.finishActiveCapture()
            guard AVAudioApplication.shared.recordPermission == .granted else {
                await lifecycleTask(for: .stop).value
                await stateHandler(.unavailable("Microphone permission is not granted"))
                return
            }
            guard isEnabled else {
                await lifecycleTask(for: .stop).value
                guard !isEnabled else {
                    await start()
                    return
                }
                await stateHandler(.unavailable("Passive listening is off"))
                return
            }

            if shouldRestart {
                await restart()
            } else if frameTask == nil {
                await start()
            } else if captureLiveness.hasReceivedFrame {
                await stateHandler(.passiveArmed)
            } else {
                await stateHandler(.unavailable("Waiting for microphone audio"))
            }
        }

        func stop() async {
            isEnabled = false
            guard !restartGate.isActiveCaptureInProgress else { return }
            restartGate.reset()
            await lifecycleTask(for: .stop).value
        }

        private func stopRuntime() async {
            captureLivenessTask?.cancel()
            captureLivenessTask = nil
            captureLiveness.stop()
            frameTask?.cancel()
            frameTask = nil
            if let coordinator {
                await coordinator.shutdown()
            }
            coordinator = nil
            await captureService.stopContinuousCapture()
        }

        private func lifecycleTask(
            for operation: MacPassiveListeningLifecycleOperation
        ) -> Task<Void, Never> {
            if lifecycleOperation == operation, let lifecycleTask {
                return lifecycleTask
            }

            lifecycleGeneration += 1
            let generation = lifecycleGeneration
            let precedingTask = lifecycleTask
            let task = Task { [weak self] in
                if let precedingTask {
                    await precedingTask.value
                }
                guard let self else { return }
                await self.performLifecycle(operation)
                await self.lifecycleDidFinish(generation: generation, operation: operation)
            }
            lifecycleOperation = operation
            lifecycleTask = task
            return task
        }

        private func performLifecycle(_ operation: MacPassiveListeningLifecycleOperation) async {
            switch operation {
            case .start:
                await startRuntime()
            case .stop:
                await stopRuntime()
            case .restart:
                await stopRuntime()
                await startRuntime()
            }
        }

        private func lifecycleDidFinish(
            generation: Int,
            operation: MacPassiveListeningLifecycleOperation
        ) {
            if operation == .restart {
                restartGate.finishRestart()
            }
            guard generation == lifecycleGeneration else { return }
            lifecycleOperation = nil
            lifecycleTask = nil
        }

        private func waitForLifecycleDrain() async {
            while let lifecycleTask {
                await lifecycleTask.value
            }
        }

        private func ingest(
            _ frame: AudioCaptureFrame,
            with coordinator: MacPassiveListeningCoordinator
        ) async {
            guard self.coordinator === coordinator else { return }
            let receivedFirstFrame = !captureLiveness.hasReceivedFrame
            captureLiveness.recordFrame(at: ProcessInfo.processInfo.systemUptime)
            if receivedFirstFrame, !restartGate.isActiveCaptureInProgress {
                await stateHandler(.passiveArmed)
            }
            await coordinator.ingest(frame)
            guard self.coordinator === coordinator else { return }
            await stateHandler(await coordinator.snapshot().state)
        }

        private func startCaptureLivenessWatchdog() {
            captureLivenessTask?.cancel()
            captureLivenessTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    guard !Task.isCancelled else { return }
                    await self?.recoverIfCaptureTimedOut()
                }
            }
        }

        private func recoverIfCaptureTimedOut() async {
            guard isEnabled else { return }

            let uptime = ProcessInfo.processInfo.systemUptime
            let capturedThroughSample = await captureService.currentAudioCaptureSamplePosition()
            captureLiveness.recordCaptureProgress(
                through: capturedThroughSample,
                at: uptime
            )
            guard captureLiveness.isTimedOut(at: uptime) else { return }

            captureLiveness.stop()
            if !restartGate.isActiveCaptureInProgress {
                await stateHandler(.unavailable("Microphone capture stopped"))
            }
            await restart()
        }
    }
#endif
