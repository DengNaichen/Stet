#if os(macOS)
    import Foundation
    import StetCore

    struct MeetingSessionProcessor: Sendable {
        var sampleRate: Int
        var diarize: @Sendable ([Float]) async throws -> [PassiveDiarizedRegion]
        var transcribe: @Sendable ([Float]) async throws -> String
        var identify: @Sendable ([Float]) async throws -> PassiveSpeakerMatch

        func process(samples: [Float]) async throws -> [MeetingTranscriptTurn] {
            guard !samples.isEmpty else { return [] }

            let regions = try await diarize(samples)
            if regions.isEmpty {
                let text = (try? await transcribe(samples)) ?? ""
                guard !text.isEmpty else { return [] }
                return [
                    MeetingTranscriptTurn(
                        startSeconds: 0,
                        endSeconds: Double(samples.count) / Double(sampleRate),
                        speakerLabel: "Speaker 1",
                        text: text,
                        isOverlap: false
                    )
                ]
            }

            var identitiesByTrack: [Int: CapturedSpeakerIdentity] = [:]
            var turns: [MeetingTranscriptTurn] = []
            for region in regions {
                let slice = Self.slice(samples, start: region.startSample, end: region.endSample)
                let identity: CapturedSpeakerIdentity
                if region.isOverlap {
                    identity = .unresolved
                } else if let track = region.speakerTrack {
                    if let cached = identitiesByTrack[track] {
                        identity = cached
                    } else {
                        let match =
                            (try? await identify(slice))
                            ?? PassiveSpeakerMatch(identity: .other, similarity: nil)
                        identity = match.identity == .unresolved ? .other : match.identity
                        identitiesByTrack[track] = identity
                    }
                } else {
                    identity = .unresolved
                }

                let text = (try? await transcribe(slice)) ?? ""

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

        nonisolated static func slice(_ samples: [Float], start: Int, end: Int) -> [Float] {
            let lower = max(0, min(start, samples.count))
            let upper = max(lower, min(end, samples.count))
            return Array(samples[lower..<upper])
        }
    }
#endif
