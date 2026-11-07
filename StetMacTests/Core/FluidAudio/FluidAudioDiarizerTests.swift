#if os(macOS)
    import FluidAudio
    import Testing

    @testable import Stet

    @Suite("FluidAudio Diarizer")
    struct FluidAudioDiarizerTests {

        @Test func emitsOnlyFinalizedSortformerRegions() {
            let regions = FluidAudioDiarizer.finalizedRegions(from: [
                segment(track: 0, start: 0, end: 8_000, confidence: 0.8),
                segment(track: 1, start: 8_000, end: 16_000, confidence: 0.7, finalized: false),
            ])

            #expect(regions.count == 1)
            #expect(regions.first?.speakerTrack == 0)
            #expect(regions.first?.startSample == 0)
            #expect(regions.first?.endSample == 8_000)
        }

        @Test func keepsActivityAndIdentityScoresSeparate() throws {
            var region = try #require(
                FluidAudioDiarizer.finalizedRegions(from: [
                    segment(track: 0, start: 0, end: 8_000, confidence: 0.76)
                ]).first
            )

            region.identitySimilarity = 0.93

            #expect(region.activityConfidence == 0.76)
            #expect(region.identitySimilarity == 0.93)
        }

        @Test func unionsOverlappingTracksOnce() {
            let regions = FluidAudioDiarizer.finalizedRegions(from: [
                segment(track: 0, start: 0, end: 100, confidence: 0.7),
                segment(track: 1, start: 40, end: 120, confidence: 0.8),
                segment(track: 2, start: 60, end: 80, confidence: 0.9),
            ])

            #expect(
                regions == [
                    DiarizedRegion(
                        speakerTrack: 0,
                        startSample: 0,
                        endSample: 40,
                        activityConfidence: 0.7,
                        isOverlap: false
                    ),
                    DiarizedRegion(
                        speakerTrack: nil,
                        startSample: 40,
                        endSample: 100,
                        activityConfidence: 0.9,
                        isOverlap: true
                    ),
                    DiarizedRegion(
                        speakerTrack: 1,
                        startSample: 100,
                        endSample: 120,
                        activityConfidence: 0.8,
                        isOverlap: false
                    ),
                ])
        }

        private func segment(
            track: Int,
            start: Int,
            end: Int,
            confidence: Double,
            finalized: Bool = true
        ) -> FluidAudioSpeakerTrackSegment {
            FluidAudioSpeakerTrackSegment(
                speakerTrack: track,
                startSample: start,
                endSample: end,
                activityConfidence: confidence,
                isFinalized: finalized
            )
        }
    }
#endif
