#if os(macOS)
    @preconcurrency import FluidAudio
    import Foundation

    nonisolated enum PassiveVoiceActivityEvent: Equatable, Sendable {
        case speechStarted(sampleIndex: Int)
        case speechEnded(sampleIndex: Int)
    }

    nonisolated struct PassiveVoiceActivityObservation: Equatable, Sendable {
        let event: PassiveVoiceActivityEvent?
        let probability: Float
        let isSpeechActive: Bool
    }

    nonisolated struct FluidAudioSpeakerTrackSegment: Equatable, Sendable {
        let speakerTrack: Int
        let startSample: Int
        let endSample: Int
        let activityConfidence: Double
        let isFinalized: Bool
    }

    nonisolated struct PassiveDiarizedRegion: Equatable, Sendable {
        var speakerTrack: Int?
        var startSample: Int
        var endSample: Int
        var activityConfidence: Double
        var identitySimilarity: Double?
        var isOverlap: Bool

        nonisolated init(
            speakerTrack: Int?,
            startSample: Int,
            endSample: Int,
            activityConfidence: Double,
            identitySimilarity: Double? = nil,
            isOverlap: Bool
        ) {
            self.speakerTrack = speakerTrack
            self.startSample = startSample
            self.endSample = endSample
            self.activityConfidence = activityConfidence
            self.identitySimilarity = identitySimilarity
            self.isOverlap = isOverlap
        }
    }

    actor FluidAudioPassiveSpeechAnalyzer {
        nonisolated static let sampleRate = 16_000

        private let vadManager: VadManager
        private let vadSegmentationConfig: VadSegmentationConfig
        private var vadState: VadStreamState
        private var pendingVADSamples: [Float] = []
        private let diarizer: SortformerDiarizer

        private init(
            vadManager: VadManager,
            vadState: VadStreamState,
            vadSegmentationConfig: VadSegmentationConfig,
            diarizer: SortformerDiarizer
        ) {
            self.vadManager = vadManager
            self.vadState = vadState
            self.vadSegmentationConfig = vadSegmentationConfig
            self.diarizer = diarizer
        }

        nonisolated static func load(
            vadProbabilityThreshold: Float = 0.60,
            speechEndSilence: TimeInterval = 1.0,
            sortformerConfig: SortformerConfig = .default
        ) async throws -> FluidAudioPassiveSpeechAnalyzer {
            let vadManager = try await VadManager(
                config: VadConfig(defaultThreshold: vadProbabilityThreshold)
            )
            let vadState = await vadManager.makeStreamState()
            let diarizer = SortformerDiarizer(
                config: sortformerConfig,
                timelineConfig: .sortformerDefault
            )
            let models = try await SortformerModels.loadFromHuggingFace(config: sortformerConfig)
            diarizer.initialize(models: models)

            return FluidAudioPassiveSpeechAnalyzer(
                vadManager: vadManager,
                vadState: vadState,
                vadSegmentationConfig: VadSegmentationConfig(
                    minSpeechDuration: 0.25,
                    minSilenceDuration: speechEndSilence,
                    maxSpeechDuration: 30,
                    speechPadding: 0
                ),
                diarizer: diarizer
            )
        }

        func processVoiceActivity(_ samples: [Float]) async throws -> [PassiveVoiceActivityObservation] {
            guard samples.allSatisfy(\.isFinite) else { return [] }
            pendingVADSamples.append(contentsOf: samples)

            var observations: [PassiveVoiceActivityObservation] = []
            var processedCount = 0
            while pendingVADSamples.count - processedCount >= VadManager.chunkSize {
                let end = processedCount + VadManager.chunkSize
                let chunk = Array(pendingVADSamples[processedCount..<end])
                let result = try await vadManager.processStreamingChunk(
                    chunk,
                    state: vadState,
                    config: vadSegmentationConfig
                )
                vadState = result.state
                observations.append(Self.observation(from: result))
                processedCount = end
            }
            if processedCount > 0 {
                pendingVADSamples.removeFirst(processedCount)
            }
            return observations
        }

        func resetVoiceActivity() async {
            pendingVADSamples.removeAll(keepingCapacity: true)
            vadState = await vadManager.makeStreamState()
        }

        func addAcceptedAudio(_ samples: [Float]) throws -> [PassiveDiarizedRegion] {
            guard samples.allSatisfy(\.isFinite) else { return [] }
            _ = try diarizer.process(samples: samples, sourceSampleRate: Double(Self.sampleRate))
            return acceptedRegionsSnapshot()
        }

        func finalizeAcceptedAudio() throws -> [PassiveDiarizedRegion] {
            try diarizer.finalizeSession()
            return acceptedRegionsSnapshot()
        }

        func resetAcceptedAudio() {
            diarizer.reset()
        }

        private func acceptedRegionsSnapshot() -> [PassiveDiarizedRegion] {
            let segments = diarizer.timeline.speakers.values.flatMap(\.finalizedSegments).map {
                FluidAudioSpeakerTrackSegment(
                    speakerTrack: $0.speakerIndex,
                    startSample: Int((Double($0.startTime) * Double(Self.sampleRate)).rounded()),
                    endSample: Int((Double($0.endTime) * Double(Self.sampleRate)).rounded()),
                    activityConfidence: Double($0.confidence),
                    isFinalized: $0.isFinalized
                )
            }
            return Self.finalizedRegions(from: segments)
        }

        nonisolated static func observation(
            from result: VadStreamResult
        ) -> PassiveVoiceActivityObservation {
            let event = result.event.map { event in
                switch event.kind {
                case .speechStart:
                    PassiveVoiceActivityEvent.speechStarted(sampleIndex: event.sampleIndex)
                case .speechEnd:
                    PassiveVoiceActivityEvent.speechEnded(sampleIndex: event.sampleIndex)
                }
            }
            return PassiveVoiceActivityObservation(
                event: event,
                probability: result.probability,
                isSpeechActive: result.state.triggered
            )
        }

        nonisolated static func finalizedRegions(
            from segments: [FluidAudioSpeakerTrackSegment]
        ) -> [PassiveDiarizedRegion] {
            let finalized = segments.filter {
                $0.isFinalized && $0.speakerTrack >= 0 && $0.startSample >= 0
                    && $0.endSample > $0.startSample && $0.activityConfidence.isFinite
            }
            let boundaries = Set(finalized.flatMap { [$0.startSample, $0.endSample] }).sorted()
            guard boundaries.count > 1 else { return [] }

            // ponytail: O(n²) is bounded by Sortformer's four tracks; replace only if that ceiling changes.
            var regions: [PassiveDiarizedRegion] = []
            for index in 0..<(boundaries.count - 1) {
                let start = boundaries[index]
                let end = boundaries[index + 1]
                let active = finalized.filter { $0.startSample < end && $0.endSample > start }
                guard !active.isEmpty else { continue }

                let overlap = Set(active.map(\.speakerTrack)).count > 1
                let next = PassiveDiarizedRegion(
                    speakerTrack: overlap ? nil : active[0].speakerTrack,
                    startSample: start,
                    endSample: end,
                    activityConfidence: active.map(\.activityConfidence).max() ?? 0,
                    isOverlap: overlap
                )

                if let lastIndex = regions.indices.last,
                    regions[lastIndex].endSample == next.startSample,
                    regions[lastIndex].speakerTrack == next.speakerTrack,
                    regions[lastIndex].isOverlap == next.isOverlap
                {
                    regions[lastIndex].endSample = next.endSample
                    regions[lastIndex].activityConfidence = max(
                        regions[lastIndex].activityConfidence,
                        next.activityConfidence
                    )
                } else {
                    regions.append(next)
                }
            }
            return regions
        }
    }
#endif
