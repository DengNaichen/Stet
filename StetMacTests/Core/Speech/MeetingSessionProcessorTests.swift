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
            #expect(turns.map(\.speakerLabel) == ["Me", "Me", "Unresolved", "Speaker 2"])
            #expect(turns[2].isOverlap)
            #expect(turns.allSatisfy { $0.text == "text" })
        }
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
