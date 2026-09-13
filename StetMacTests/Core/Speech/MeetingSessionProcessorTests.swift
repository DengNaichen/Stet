#if os(macOS)
    import Foundation
    import StetCore
    import Testing

    @testable import Stet

    @Suite("Meeting Session Processor")
    struct MeetingSessionProcessorTests {
        @Test func emptySamplesProduceNoTurns() async throws {
            let processor = MeetingSessionProcessor(
                sampleRate: 16_000,
                diarize: { _ in [] },
                transcribe: { _ in "should not run" },
                identify: { _ in PassiveSpeakerMatch(identity: .self, similarity: 1) }
            )

            let turns = try await processor.process(samples: [])
            #expect(turns.isEmpty)
        }

        @Test func missingRegionsFallBackToASingleSpeakerTurn() async throws {
            let processor = MeetingSessionProcessor(
                sampleRate: 16_000,
                diarize: { _ in [] },
                transcribe: { _ in "solo" },
                identify: { _ in PassiveSpeakerMatch(identity: .other, similarity: nil) }
            )

            let turns = try await processor.process(samples: [0, 0, 0, 0])
            #expect(turns.count == 1)
            #expect(turns[0].speakerLabel == "Speaker 1")
            #expect(turns[0].text == "solo")
            #expect(!turns[0].isOverlap)
        }

        @Test func overlapIsUnresolvedAndIdentityIsCachedPerTrack() async throws {
            let identifyCount = CallCounter()
            let processor = MeetingSessionProcessor(
                sampleRate: 16_000,
                diarize: { _ in
                    [
                        PassiveDiarizedRegion(
                            speakerTrack: 0,
                            startSample: 0,
                            endSample: 2,
                            activityConfidence: 1,
                            isOverlap: false
                        ),
                        PassiveDiarizedRegion(
                            speakerTrack: 0,
                            startSample: 2,
                            endSample: 4,
                            activityConfidence: 1,
                            isOverlap: false
                        ),
                        PassiveDiarizedRegion(
                            speakerTrack: nil,
                            startSample: 4,
                            endSample: 6,
                            activityConfidence: 1,
                            isOverlap: true
                        ),
                        PassiveDiarizedRegion(
                            speakerTrack: 1,
                            startSample: 6,
                            endSample: 8,
                            activityConfidence: 1,
                            isOverlap: false
                        ),
                    ]
                },
                transcribe: { _ in "text" },
                identify: { _ in
                    let count = identifyCount.increment()
                    if count == 1 {
                        return PassiveSpeakerMatch(identity: .self, similarity: 0.9)
                    }
                    return PassiveSpeakerMatch(identity: .other, similarity: 0.2)
                }
            )

            let turns = try await processor.process(samples: Array(repeating: 0.1, count: 8))
            #expect(identifyCount.value == 2)
            #expect(turns.map(\.speakerLabel) == ["Me", "Unresolved", "Speaker 2"])
            #expect(turns[1].isOverlap)
            #expect(turns.allSatisfy { $0.text == "text" })
        }

        @Test func transcriptionLifecycleFinishesAfterSuccessAndFailure() async throws {
            let successPrepare = CallCounter()
            let successFinish = CallCounter()
            let success = MeetingSessionProcessor(
                sampleRate: 100,
                prepareTranscription: { successPrepare.increment() },
                finishTranscription: { successFinish.increment() },
                diarize: { _ in [] },
                transcribe: { _ in "ok" },
                identify: { _ in PassiveSpeakerMatch(identity: .other, similarity: nil) }
            )
            _ = try await success.process(samples: [0.1])
            #expect(successPrepare.value == 1)
            #expect(successFinish.value == 1)

            let failurePrepare = CallCounter()
            let failureFinish = CallCounter()
            let failure = MeetingSessionProcessor(
                sampleRate: 100,
                prepareTranscription: { failurePrepare.increment() },
                finishTranscription: { failureFinish.increment() },
                diarize: { _ in throw TestFailure.expected },
                transcribe: { _ in "unused" },
                identify: { _ in PassiveSpeakerMatch(identity: .other, similarity: nil) }
            )
            await #expect(throws: TestFailure.expected) {
                _ = try await failure.process(samples: [0.1])
            }
            #expect(failurePrepare.value == 1)
            #expect(failureFinish.value == 1)
        }

        @Test func mergesSameSpeakerAcrossShortSilenceBeforeTranscription() async throws {
            let transcriptionCount = CallCounter()
            let processor = MeetingSessionProcessor(
                sampleRate: 100,
                diarize: { _ in
                    [
                        PassiveDiarizedRegion(
                            speakerTrack: 0,
                            startSample: 0,
                            endSample: 100,
                            activityConfidence: 0.8,
                            isOverlap: false
                        ),
                        PassiveDiarizedRegion(
                            speakerTrack: 0,
                            startSample: 125,
                            endSample: 200,
                            activityConfidence: 0.9,
                            isOverlap: false
                        ),
                    ]
                },
                transcribe: { samples in
                    transcriptionCount.increment()
                    #expect(samples.count == 200)
                    return "one turn"
                },
                identify: { _ in PassiveSpeakerMatch(identity: .self, similarity: 0.9) }
            )

            let turns = try await processor.process(samples: Array(repeating: 0.1, count: 200))

            #expect(transcriptionCount.value == 1)
            #expect(turns.count == 1)
            #expect(turns[0].startSeconds == 0)
            #expect(turns[0].endSeconds == 2)
        }

        @Test func preservesSpeakerChangesShortTurnsAndOverlap() {
            let regions = [
                PassiveDiarizedRegion(
                    speakerTrack: 0,
                    startSample: 0,
                    endSample: 100,
                    activityConfidence: 1,
                    isOverlap: false
                ),
                PassiveDiarizedRegion(
                    speakerTrack: 1,
                    startSample: 100,
                    endSample: 110,
                    activityConfidence: 1,
                    isOverlap: false
                ),
                PassiveDiarizedRegion(
                    speakerTrack: nil,
                    startSample: 110,
                    endSample: 120,
                    activityConfidence: 1,
                    isOverlap: true
                ),
                PassiveDiarizedRegion(
                    speakerTrack: 0,
                    startSample: 120,
                    endSample: 200,
                    activityConfidence: 1,
                    isOverlap: false
                ),
            ]

            let planned = MeetingTurnPostProcessor(sampleRate: 100)
                .plan(regions: regions, sampleCount: 200)

            #expect(planned.count == 4)
            #expect(planned.map(\.speakerTrack) == [0, 1, nil, 0])
            #expect(planned.map(\.isOverlap) == [false, false, true, false])
            #expect(planned[1].endSample - planned[1].startSample == 10)
        }

        @Test func mergeThresholdIsInclusiveAndLongerGapRemainsSeparate() {
            let regions = [
                PassiveDiarizedRegion(
                    speakerTrack: 0,
                    startSample: 0,
                    endSample: 100,
                    activityConfidence: 1,
                    isOverlap: false
                ),
                PassiveDiarizedRegion(
                    speakerTrack: 0,
                    startSample: 130,
                    endSample: 200,
                    activityConfidence: 1,
                    isOverlap: false
                ),
                PassiveDiarizedRegion(
                    speakerTrack: 0,
                    startSample: 231,
                    endSample: 300,
                    activityConfidence: 1,
                    isOverlap: false
                ),
            ]

            let planned = MeetingTurnPostProcessor(sampleRate: 100)
                .plan(regions: regions, sampleCount: 300)

            #expect(planned.count == 2)
            #expect(planned[0].startSample == 0)
            #expect(planned[0].endSample == 200)
            #expect(planned[1].startSample == 231)
        }

        @Test func clipsInvalidRegionsAndCapsTranscriptionWindows() {
            let regions = [
                PassiveDiarizedRegion(
                    speakerTrack: 0,
                    startSample: -20,
                    endSample: 250,
                    activityConfidence: 0.7,
                    isOverlap: false
                ),
                PassiveDiarizedRegion(
                    speakerTrack: 1,
                    startSample: 250,
                    endSample: 500,
                    activityConfidence: .nan,
                    isOverlap: false
                ),
            ]
            let configuration = MeetingTurnPostProcessingConfiguration(
                sameSpeakerMergeGapSeconds: 0.30,
                maximumTranscriptionWindowSeconds: 1
            )

            let planned = MeetingTurnPostProcessor(
                sampleRate: 100,
                configuration: configuration
            ).plan(regions: regions, sampleCount: 220)

            #expect(planned.map(\.startSample) == [0, 100, 200])
            #expect(planned.map(\.endSample) == [100, 200, 220])
        }
    }

    private enum TestFailure: Error {
        case expected
    }

    private final class CallCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0

        var value: Int {
            lock.withLock { count }
        }

        @discardableResult
        func increment() -> Int {
            lock.withLock {
                count += 1
                return count
            }
        }
    }
#endif
