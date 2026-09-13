#if os(macOS)
    import Foundation
    import StetCore

    struct MeetingTurnPostProcessingConfiguration: Equatable, Sendable {
        var sameSpeakerMergeGapSeconds: Double = 0.30
        var maximumTranscriptionWindowSeconds: Double = 20
    }

    struct PlannedMeetingTurn: Equatable, Sendable {
        var speakerTrack: Int?
        var startSample: Int
        var endSample: Int
        var activityConfidence: Double
        var isOverlap: Bool
    }

    struct MeetingTurnPostProcessor: Sendable {
        var sampleRate: Int
        var configuration = MeetingTurnPostProcessingConfiguration()

        func plan(
            regions: [PassiveDiarizedRegion],
            sampleCount: Int
        ) -> [PlannedMeetingTurn] {
            guard sampleRate > 0, sampleCount > 0 else { return [] }

            let mergeGap = samples(
                seconds: configuration.sameSpeakerMergeGapSeconds,
                fallback: 0
            )
            let maximumWindow = max(
                1,
                samples(
                    seconds: configuration.maximumTranscriptionWindowSeconds,
                    fallback: sampleCount
                )
            )
            let valid = regions.compactMap { region -> PlannedMeetingTurn? in
                guard region.activityConfidence.isFinite else { return nil }
                let start = max(0, min(region.startSample, sampleCount))
                let end = max(start, min(region.endSample, sampleCount))
                guard end > start else { return nil }
                return PlannedMeetingTurn(
                    speakerTrack: region.speakerTrack,
                    startSample: start,
                    endSample: end,
                    activityConfidence: region.activityConfidence,
                    isOverlap: region.isOverlap
                )
            }.sorted {
                if $0.startSample == $1.startSample { return $0.endSample < $1.endSample }
                return $0.startSample < $1.startSample
            }

            var planned: [PlannedMeetingTurn] = []
            for region in valid {
                var remainingStart = region.startSample
                while remainingStart < region.endSample {
                    let chunkEnd = min(region.endSample, remainingStart + maximumWindow)
                    let chunk = PlannedMeetingTurn(
                        speakerTrack: region.speakerTrack,
                        startSample: remainingStart,
                        endSample: chunkEnd,
                        activityConfidence: region.activityConfidence,
                        isOverlap: region.isOverlap
                    )

                    if let lastIndex = planned.indices.last,
                        canMerge(planned[lastIndex], chunk, mergeGap: mergeGap, maximumWindow: maximumWindow)
                    {
                        planned[lastIndex].endSample = max(planned[lastIndex].endSample, chunk.endSample)
                        planned[lastIndex].activityConfidence = max(
                            planned[lastIndex].activityConfidence,
                            chunk.activityConfidence
                        )
                    } else {
                        planned.append(chunk)
                    }
                    remainingStart = chunkEnd
                }
            }
            return planned
        }

        private func samples(seconds: Double, fallback: Int) -> Int {
            guard seconds.isFinite, seconds >= 0 else { return fallback }
            let samples = seconds * Double(sampleRate)
            guard samples.isFinite, samples <= Double(Int.max) else { return fallback }
            return Int(samples.rounded())
        }

        private func canMerge(
            _ lhs: PlannedMeetingTurn,
            _ rhs: PlannedMeetingTurn,
            mergeGap: Int,
            maximumWindow: Int
        ) -> Bool {
            guard !lhs.isOverlap, !rhs.isOverlap,
                let lhsTrack = lhs.speakerTrack,
                lhsTrack == rhs.speakerTrack,
                rhs.startSample >= lhs.endSample,
                rhs.startSample - lhs.endSample <= mergeGap
            else { return false }
            return rhs.endSample - lhs.startSample <= maximumWindow
        }
    }

    struct MeetingSessionProcessor: Sendable {
        var sampleRate: Int
        var turnPostProcessingConfiguration = MeetingTurnPostProcessingConfiguration()
        var prepareTranscription: @Sendable () async throws -> Void = {}
        var finishTranscription: @Sendable () async -> Void = {}
        var diarize: @Sendable ([Float]) async throws -> [PassiveDiarizedRegion]
        var transcribe: @Sendable ([Float]) async throws -> String
        var identify: @Sendable ([Float]) async throws -> PassiveSpeakerMatch

        func process(samples: [Float]) async throws -> [MeetingTranscriptTurn] {
            guard !samples.isEmpty else { return [] }

            try await prepareTranscription()
            do {
                let turns = try await processPrepared(samples: samples)
                await finishTranscription()
                return turns
            } catch {
                await finishTranscription()
                throw error
            }
        }

        private func processPrepared(samples: [Float]) async throws -> [MeetingTranscriptTurn] {
            try Task.checkCancellation()
            let regions = try await diarize(samples)
            let planner = MeetingTurnPostProcessor(
                sampleRate: sampleRate,
                configuration: turnPostProcessingConfiguration
            )
            if regions.isEmpty {
                let fallbackRegion = PassiveDiarizedRegion(
                    speakerTrack: nil,
                    startSample: 0,
                    endSample: samples.count,
                    activityConfidence: 1,
                    isOverlap: false
                )
                let windows = planner.plan(regions: [fallbackRegion], sampleCount: samples.count)
                var turns: [MeetingTranscriptTurn] = []
                for window in windows {
                    try Task.checkCancellation()
                    let slice = Self.slice(samples, start: window.startSample, end: window.endSample)
                    let text = try await transcribeRecoveringNonCancellation(slice)
                    guard !text.isEmpty else { continue }
                    turns.append(
                        MeetingTranscriptTurn(
                            startSeconds: Double(window.startSample) / Double(sampleRate),
                            endSeconds: Double(window.endSample) / Double(sampleRate),
                            speakerLabel: "Speaker 1",
                            text: text,
                            isOverlap: false
                        )
                    )
                }
                return turns
            }

            let plannedTurns = planner.plan(regions: regions, sampleCount: samples.count)
            guard !plannedTurns.isEmpty else { return [] }

            var identitiesByTrack: [Int: CapturedSpeakerIdentity] = [:]
            var turns: [MeetingTranscriptTurn] = []
            for region in plannedTurns {
                try Task.checkCancellation()
                let slice = Self.slice(samples, start: region.startSample, end: region.endSample)
                let identity: CapturedSpeakerIdentity
                if region.isOverlap {
                    identity = .unresolved
                } else if let track = region.speakerTrack {
                    if let cached = identitiesByTrack[track] {
                        identity = cached
                    } else {
                        let match = try await identifyRecoveringNonCancellation(slice)
                        identity = match.identity == .unresolved ? .other : match.identity
                        identitiesByTrack[track] = identity
                    }
                } else {
                    identity = .unresolved
                }

                let text = try await transcribeRecoveringNonCancellation(slice)

                turns.append(
                    MeetingTranscriptTurn(
                        startSeconds: Double(region.startSample) / Double(sampleRate),
                        endSeconds: Double(region.endSample) / Double(sampleRate),
                        speakerLabel: MeetingTranscriptDocument.speakerLabel(
                            identity: identity,
                            track: region.speakerTrack
                        ),
                        text: text,
                        isOverlap: region.isOverlap
                    )
                )
            }
            return turns
        }

        private func transcribeRecoveringNonCancellation(_ samples: [Float]) async throws -> String {
            do {
                return try await transcribe(samples)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                return ""
            }
        }

        private func identifyRecoveringNonCancellation(_ samples: [Float]) async throws -> PassiveSpeakerMatch {
            do {
                let match = try await identify(samples)
                return match.identity == .unresolved
                    ? PassiveSpeakerMatch(identity: .other, similarity: match.similarity)
                    : match
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                return PassiveSpeakerMatch(identity: .other, similarity: nil)
            }
        }

        nonisolated static func slice(_ samples: [Float], start: Int, end: Int) -> [Float] {
            let lower = max(0, min(start, samples.count))
            let upper = max(lower, min(end, samples.count))
            return Array(samples[lower..<upper])
        }
    }
#endif
