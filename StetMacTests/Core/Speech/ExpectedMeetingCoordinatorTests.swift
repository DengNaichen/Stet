#if os(macOS)
    import Foundation
    import Testing

    @testable import Stet

    @Suite("Expected Meeting Coordinator")
    struct ExpectedMeetingCoordinatorTests {
        @Test func syncIsIdempotentAndPersistsMeetings() async throws {
            let fileURL = TestSupport.temporaryDirectoryURL().appendingPathComponent("expected.json")
            let reminders = ReminderRecorder()
            let now = Date(timeIntervalSince1970: 1_704_067_200)
            let coordinator = ExpectedMeetingCoordinator(
                store: ExpectedMeetingStore(fileURL: fileURL),
                reminders: reminders,
                now: { now }
            )
            let input = makeInput(start: now.addingTimeInterval(3_600))

            let first = try await coordinator.sync(
                windowStart: now,
                windowEnd: now.addingTimeInterval(86_400),
                inputs: [input]
            )
            let second = try await coordinator.sync(
                windowStart: now,
                windowEnd: now.addingTimeInterval(86_400),
                inputs: [input]
            )

            #expect(first.created == 1)
            #expect(first.updated == 0)
            #expect(second.created == 0)
            #expect(second.updated == 0)
            #expect(first.meetings.first?.id == second.meetings.first?.id)
            #expect(try ExpectedMeetingStore(fileURL: fileURL).load() == second.meetings)
        }

        @Test func missingMeetingInWindowIsCancelled() async throws {
            let fileURL = TestSupport.temporaryDirectoryURL().appendingPathComponent("expected.json")
            let reminders = ReminderRecorder()
            let now = Date(timeIntervalSince1970: 1_704_067_200)
            let coordinator = ExpectedMeetingCoordinator(
                store: ExpectedMeetingStore(fileURL: fileURL),
                reminders: reminders,
                now: { now }
            )
            _ = try await coordinator.sync(
                windowStart: now,
                windowEnd: now.addingTimeInterval(86_400),
                inputs: [makeInput(start: now.addingTimeInterval(3_600))]
            )

            let result = try await coordinator.sync(
                windowStart: now,
                windowEnd: now.addingTimeInterval(86_400),
                inputs: []
            )

            #expect(result.cancelled == 1)
            #expect(result.meetings.first?.status == .cancelled)
            #expect(await reminders.cancelledCount == 1)
        }

        @Test func markRecordedLinksExpectedMeetingToSession() async throws {
            let fileURL = TestSupport.temporaryDirectoryURL().appendingPathComponent("expected.json")
            let now = Date(timeIntervalSince1970: 1_704_067_200)
            let coordinator = ExpectedMeetingCoordinator(
                store: ExpectedMeetingStore(fileURL: fileURL),
                reminders: ReminderRecorder(),
                now: { now }
            )
            let result = try await coordinator.sync(
                windowStart: now,
                windowEnd: now.addingTimeInterval(86_400),
                inputs: [makeInput(start: now.addingTimeInterval(3_600))]
            )
            let id = try #require(result.meetings.first?.id)

            try await coordinator.markRecorded(id: id, meetingID: "2026-09-12 21-00-00")
            let recording = await coordinator.meeting(id: id)
            #expect(recording?.status == .recording)
            #expect(recording?.recordedMeetingID == "2026-09-12 21-00-00")

            try await coordinator.markCompleted(id: id)
            #expect(await coordinator.meeting(id: id)?.status == .completed)
        }

        @Test func repeatedSyncDoesNotReactivateSkippedMeeting() async throws {
            let fileURL = TestSupport.temporaryDirectoryURL().appendingPathComponent("expected.json")
            let now = Date(timeIntervalSince1970: 1_704_067_200)
            let coordinator = ExpectedMeetingCoordinator(
                store: ExpectedMeetingStore(fileURL: fileURL),
                reminders: ReminderRecorder(),
                now: { now }
            )
            let input = makeInput(start: now.addingTimeInterval(3_600))
            let first = try await coordinator.sync(
                windowStart: now,
                windowEnd: now.addingTimeInterval(86_400),
                inputs: [input]
            )
            let id = try #require(first.meetings.first?.id)
            try await coordinator.skip(id: id)

            let repeated = try await coordinator.sync(
                windowStart: now,
                windowEnd: now.addingTimeInterval(86_400),
                inputs: [input]
            )

            #expect(repeated.meetings.first?.status == .skipped)
        }

        private func makeInput(start: Date) -> ExpectedMeetingInput {
            ExpectedMeetingInput(
                source: "calendar",
                externalID: "event-1",
                scheduledStartAt: start,
                scheduledEndAt: start.addingTimeInterval(1_800),
                title: "Project sync",
                attendees: [MeetingAttendee(name: "Taylor", email: "taylor@example.com")],
                meetingURL: URL(string: "https://example.com/meeting"),
                notes: nil,
                sourceModifiedAt: nil,
                status: .scheduled
            )
        }
    }

    private actor ReminderRecorder: ExpectedMeetingReminderScheduling {
        private(set) var scheduledCount = 0
        private(set) var cancelledCount = 0

        func schedule(_ meeting: ExpectedMeeting) {
            scheduledCount += 1
        }

        func cancel(_ meeting: ExpectedMeeting) {
            cancelledCount += 1
        }
    }
#endif
