#if os(macOS)
    import Foundation
    import StetCore
    import Testing

    @testable import Stet

    @Suite("Meeting Transcript Document")
    struct MeetingTranscriptDocumentTests {
        @Test func speakerLabelsMatchIdentityAndTrack() {
            #expect(
                MeetingTranscriptDocument.speakerLabel(identity: .self, track: 0) == "Me"
            )
            #expect(
                MeetingTranscriptDocument.speakerLabel(identity: .other, track: 0) == "Speaker 1"
            )
            #expect(
                MeetingTranscriptDocument.speakerLabel(identity: .other, track: 3) == "Speaker 4"
            )
            #expect(
                MeetingTranscriptDocument.speakerLabel(identity: .unresolved, track: 1) == "Unresolved"
            )
            #expect(
                MeetingTranscriptDocument.speakerLabel(
                    identity: .known(profileID: UUID(), displayName: "Alex"),
                    track: 2
                ) == "Alex"
            )
        }

        @Test func markdownIncludesStartTimeAndSpeakerTurns() {
            let startedAt = Date(timeIntervalSince1970: 1_704_067_200)
            let endedAt = startedAt.addingTimeInterval(95)
            let markdown = MeetingTranscriptDocument.markdown(
                startedAt: startedAt,
                endedAt: endedAt,
                turns: [
                    MeetingTranscriptTurn(
                        startSeconds: 0,
                        endSeconds: 2,
                        speakerLabel: "Me",
                        text: "Hello",
                        isOverlap: false
                    ),
                    MeetingTranscriptTurn(
                        startSeconds: 2,
                        endSeconds: 4,
                        speakerLabel: "Speaker 2",
                        text: "Hi",
                        isOverlap: false
                    ),
                    MeetingTranscriptTurn(
                        startSeconds: 4,
                        endSeconds: 6,
                        speakerLabel: "Unresolved",
                        text: "both",
                        isOverlap: true
                    ),
                ]
            )

            #expect(markdown.contains("**Me**"))
            #expect(markdown.contains("Hello"))
            #expect(markdown.contains("**Speaker 2**"))
            #expect(markdown.contains("**Unresolved**"))
            #expect(markdown.contains("overlapping"))
            #expect(markdown.contains("1 min 35s"))
            #expect(!markdown.localizedCaseInsensitiveContains("rewrite"))
        }
    }
#endif
