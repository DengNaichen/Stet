#if os(macOS)
    import FluidAudio
    import Testing

    @testable import Stet

    @Suite("FluidAudio Passive Speech Analyzer")
    struct FluidAudioPassiveSpeechAnalyzerTests {
        @Test func mapsStreamingVADStartAndEndEvents() {
            let started = FluidAudioPassiveSpeechAnalyzer.observation(
                from: VadStreamResult(
                    state: VadStreamState(triggered: true, processedSamples: 4_096),
                    event: VadStreamEvent(kind: .speechStart, sampleIndex: 0),
                    probability: 0.82
                )
            )
            let ended = FluidAudioPassiveSpeechAnalyzer.observation(
                from: VadStreamResult(
                    state: VadStreamState(triggered: false, processedSamples: 20_480),
                    event: VadStreamEvent(kind: .speechEnd, sampleIndex: 16_000),
                    probability: 0.08
                )
            )

            #expect(started.event == .speechStarted(sampleIndex: 0))
            #expect(started.isSpeechActive)
            #expect(started.probability == 0.82)
            #expect(ended.event == .speechEnded(sampleIndex: 16_000))
            #expect(!ended.isSpeechActive)
        }

        @Test func emitsOnlyFinalizedSortformerRegions() {
            let regions = FluidAudioPassiveSpeechAnalyzer.finalizedRegions(from: [
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
                FluidAudioPassiveSpeechAnalyzer.finalizedRegions(from: [
                    segment(track: 0, start: 0, end: 8_000, confidence: 0.76)
                ]).first
            )

            region.identitySimilarity = 0.93

            #expect(region.activityConfidence == 0.76)
            #expect(region.identitySimilarity == 0.93)
        }

        @Test func unionsOverlappingTracksOnce() {
            let regions = FluidAudioPassiveSpeechAnalyzer.finalizedRegions(from: [
                segment(track: 0, start: 0, end: 100, confidence: 0.7),
                segment(track: 1, start: 40, end: 120, confidence: 0.8),
                segment(track: 2, start: 60, end: 80, confidence: 0.9),
            ])

            #expect(
                regions == [
                    PassiveDiarizedRegion(
                        speakerTrack: 0,
                        startSample: 0,
                        endSample: 40,
                        activityConfidence: 0.7,
                        isOverlap: false
                    ),
                    PassiveDiarizedRegion(
                        speakerTrack: nil,
                        startSample: 40,
                        endSample: 100,
                        activityConfidence: 0.9,
                        isOverlap: true
                    ),
                    PassiveDiarizedRegion(
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
