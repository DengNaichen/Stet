#if os(macOS)
    @preconcurrency import FluidAudio
    import Foundation
    import StetCore

    nonisolated struct FluidAudioSpeakerTrackSegment: Equatable, Sendable {
        let speakerTrack: Int
        let startSample: Int
        let endSample: Int
        let activityConfidence: Double
        let isFinalized: Bool
    }

    nonisolated struct DiarizedRegion: Equatable, Sendable {
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

    actor FluidAudioDiarizer {
        nonisolated static let sampleRate = 16_000

        private let diarizer: SortformerDiarizer

        private init(diarizer: SortformerDiarizer) {
            self.diarizer = diarizer
        }

        nonisolated static func load(
            sortformerConfig: SortformerConfig = .default
        ) async throws -> FluidAudioDiarizer {
            FluidAudioModelManager.configureDownloadRegistry()
            let diarizer = SortformerDiarizer(
                config: sortformerConfig,
                timelineConfig: .sortformerDefault
            )
            let models = try await SortformerModels.loadFromHuggingFace(config: sortformerConfig)
            diarizer.initialize(models: models)

            return FluidAudioDiarizer(diarizer: diarizer)
        }

        func addAcceptedAudio(_ samples: [Float]) throws -> [DiarizedRegion] {
            guard samples.allSatisfy(\.isFinite) else { return [] }
            _ = try diarizer.process(samples: samples, sourceSampleRate: Double(Self.sampleRate))
            return acceptedRegionsSnapshot()
        }

        func finalizeAcceptedAudio() throws -> [DiarizedRegion] {
            try diarizer.finalizeSession()
            return acceptedRegionsSnapshot()
        }

        private func acceptedRegionsSnapshot() -> [DiarizedRegion] {
            let segments = diarizer.timeline.speakers.values.flatMap(\.finalizedSegments).map {
                FluidAudioSpeakerTrackSegment(
                    speakerTrack: $0.speakerIndex,
                    startSample: Int((Double($0.startTime) * Double(Self.sampleRate)).rounded()),
                    endSample: Int((Double($0.endTime) * Double(Self.sampleRate)).rounded()),
                    activityConfidence: Double($0.activity),
                    isFinalized: $0.isFinalized
                )
            }
            return Self.finalizedRegions(from: segments)
        }

        nonisolated static func finalizedRegions(
            from segments: [FluidAudioSpeakerTrackSegment]
        ) -> [DiarizedRegion] {
            let finalized = segments.filter {
                $0.isFinalized && $0.speakerTrack >= 0 && $0.startSample >= 0
                    && $0.endSample > $0.startSample && $0.activityConfidence.isFinite
            }
            let boundaries = Set(finalized.flatMap { [$0.startSample, $0.endSample] }).sorted()
            guard boundaries.count > 1 else { return [] }

            // ponytail: O(n²) is bounded by Sortformer's four tracks; replace only if that ceiling changes.
            var regions: [DiarizedRegion] = []
            for index in 0..<(boundaries.count - 1) {
                let start = boundaries[index]
                let end = boundaries[index + 1]
                let active = finalized.filter { $0.startSample < end && $0.endSample > start }
                guard !active.isEmpty else { continue }

                let overlap = Set(active.map(\.speakerTrack)).count > 1
                let next = DiarizedRegion(
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
