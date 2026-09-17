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

        @Test func markdownIncludesExpectedMeetingMetadata() {
            let scheduledStart = Date(timeIntervalSince1970: 1_704_067_200)
            let metadata = MeetingMetadata(
                expectedMeeting: ExpectedMeeting(
                    id: UUID(),
                    source: "calendar",
                    externalID: "event-1",
                    scheduledStartAt: scheduledStart,
                    scheduledEndAt: scheduledStart.addingTimeInterval(1_800),
                    title: "Project sync",
                    attendees: [MeetingAttendee(name: "Taylor", email: nil)],
                    meetingURL: URL(string: "https://example.com/meeting"),
                    notes: nil,
                    sourceModifiedAt: nil,
                    status: .scheduled,
                    recordedMeetingID: nil
                )
            )
            let markdown = MeetingTranscriptDocument.markdown(
                startedAt: scheduledStart.addingTimeInterval(60),
                endedAt: scheduledStart.addingTimeInterval(120),
                turns: [],
                metadata: metadata
            )

            #expect(markdown.contains("# Project sync"))
            #expect(markdown.contains("Attendees: Taylor"))
            #expect(markdown.contains("Meeting: https://example.com/meeting"))
            #expect(markdown.contains("Scheduled:"))
        }

        @Test func continuousSpeakerMergesAcrossWindowsAndLongPauses() {
            let texts = ["第一句。", "Second sentence.", String(repeating: "长", count: 401)]
            let turns = zip([0.0, 20, 180], texts).map { start, text in
                MeetingTranscriptTurn(
                    startSeconds: start, endSeconds: start + 20,
                    speakerLabel: "Speaker 1", text: text, isOverlap: false)
            }
            let markdown = render(turns)
            #expect(markdown.components(separatedBy: "**Speaker 1**").count - 1 == 1)
            #expect(markdown.contains("**Speaker 1** (0:00–3:20)"))
            #expect(markdown.contains(texts.joined(separator: "\n")))
        }

        @Test func emptySameSpeakerTurnsAreHiddenWithoutInterruptingText() {
            let markdown = render([
                turn("Speaker 1", "Hello"), turn("Speaker 1", " \n\t"), turn("Speaker 1", "world"),
            ])
            #expect(markdown.contains("Hello\nworld"))
            #expect(markdown.components(separatedBy: "**Speaker 1**").count - 1 == 1)
            #expect(!markdown.contains("_No text_"))
        }

        @Test func hiddenSpeakerChangesAndOverlapStillInterruptParagraphs() {
            for interruption in [turn("Speaker 2", ""), turn("Unresolved", "", overlap: true)] {
                let markdown = render([
                    turn("Speaker 1", "before"), interruption,
                    turn("Speaker 1", ""), turn("Speaker 1", "after"),
                ])
                #expect(markdown.components(separatedBy: "**Speaker 1**").count - 1 == 2)
                #expect(!markdown.contains("_No text_"))
            }
        }

        @Test func speakerChangesAndConsecutiveOverlapRemainSeparate() {
            let markdown = render([
                turn("Speaker 1", "A"), turn("Speaker 2", "嗯"), turn("Speaker 1", "B"),
                turn("Unresolved", "overlap one", overlap: true),
                turn("Unresolved", "overlap two", overlap: true),
            ])
            #expect(markdown.components(separatedBy: "**Speaker 1**").count - 1 == 2)
            #expect(markdown.contains("嗯"))
            #expect(markdown.components(separatedBy: " · overlapping").count - 1 == 2)
        }

        @Test func allEmptyTurnsRenderNoSpeechMessage() {
            let markdown = render([turn("Speaker 1", ""), turn("Unresolved", " \n", overlap: true)])
            #expect(markdown.contains("No speech was recognized in this recording."))
            #expect(!markdown.contains("**Speaker"))
            #expect(!markdown.contains("_No text_"))
        }

        private func turn(_ speaker: String, _ text: String, overlap: Bool = false) -> MeetingTranscriptTurn {
            MeetingTranscriptTurn(
                startSeconds: 0, endSeconds: 1, speakerLabel: speaker, text: text, isOverlap: overlap)
        }

        private func render(_ turns: [MeetingTranscriptTurn]) -> String {
            let start = Date(timeIntervalSince1970: 1_704_067_200)
            return MeetingTranscriptDocument.markdown(
                startedAt: start, endedAt: start.addingTimeInterval(200), turns: turns)
        }
    }
#endif
