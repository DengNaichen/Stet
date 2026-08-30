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
            guard frameTask == nil else { return }
            guard AVAudioApplication.shared.recordPermission == .granted else {
                await stateHandler(.unavailable("Microphone permission is not granted"))
                return
            }
            MacPassiveListeningCoordinator.cleanupOrphanedTemporaryAudio()
            do {
                let coordinator = try await makeCoordinator()
                let stream = await captureService.makeAudioCaptureFrameStream()
                try await captureService.startContinuousCapture()
                _ = await captureService.beginNextAudioCaptureEpoch()
                let epoch = await captureService.currentAudioCaptureEpoch()
                await coordinator.arm(epoch: epoch)
                self.coordinator = coordinator
                await stateHandler(.passiveArmed)
                frameTask = Task { [weak self] in
                    for await frame in stream {
                        guard !Task.isCancelled else { break }
                        await coordinator.ingest(frame)
                        await self?.publishState()
                    }
                }
            } catch {
                coordinator = nil
                await stateHandler(.unavailable(error.localizedDescription))
            }
        }

        func restart() async {
            await stop()
            await start()
        }

        func revalidatePermission() async {
            if AVAudioApplication.shared.recordPermission == .granted {
                if frameTask == nil {
                    await start()
                }
            } else {
                frameTask?.cancel()
                frameTask = nil
                if let coordinator {
                    await coordinator.setUnavailable("Microphone permission is not granted")
                }
                coordinator = nil
                await captureService.stopContinuousCapture()
                await stateHandler(.unavailable("Microphone permission is not granted"))
            }
        }

        func beginActive() async {
            guard let coordinator else { return }
            _ = await captureService.beginNextAudioCaptureEpoch()
            let epoch = await captureService.currentAudioCaptureEpoch()
            await coordinator.hotkeyDown(newEpoch: epoch)
            await stateHandler(.active)
        }

        func resumePassive() async {
            guard let coordinator else { return }
            _ = await captureService.beginNextAudioCaptureEpoch()
            let epoch = await captureService.currentAudioCaptureEpoch()
            await coordinator.hotkeyUp(newEpoch: epoch)
            await stateHandler(.passiveArmed)
        }

        func stop() async {
            frameTask?.cancel()
            frameTask = nil
            if let coordinator {
                await coordinator.shutdown()
            }
            coordinator = nil
            await captureService.stopContinuousCapture()
        }

        private func publishState() async {
            guard let coordinator else { return }
            await stateHandler(await coordinator.snapshot().state)
        }
    }
#endif
