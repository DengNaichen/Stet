#if os(macOS)
    import Foundation
    import Testing

    @testable import Stet

    @MainActor
    @Suite("Meeting workflow")
    struct MacMeetingWorkflowControllerTests {
        private let now = Date(timeIntervalSince1970: 1_700_000_000)

        @Test(arguments: [MacMeetingRecordingPhase.idle, .failed("transcription failed")])
        func processingCompletionFinishesLinkedMeetingOnce(terminal: MacMeetingRecordingPhase) async {
            let expected = ExpectedMeetingsStub()
            let recording = MeetingRecordingStub()
            let meeting = makeMeeting()
            expected.value = meeting
            var published: [MacMeetingRecordingPhase] = []
            var notifications: [(MacMeetingRecordingPhase, MacMeetingRecordingPhase)] = []
            let workflow = MacMeetingWorkflowController(
                recording: recording, expectedMeetings: expected,
                publishLivePhase: { published.append($0) },
                notifyPhase: { notifications.append(($0, $1)) }, now: { now })
            await workflow.observeRecording()
            workflow.startExpectedMeeting(id: meeting.id)
            let linked = await TestSupport.eventuallyAsync {
                await MainActor.run { expected.recordedIDs == [meeting.id] }
            }
            #expect(linked)
            #expect(expected.folderNames == ["session-folder"])
            #expect(workflow.isBusy)
            #expect(workflow.phase == recording.phase)

            recording.emit(.processing)
            #expect(expected.completedIDs.isEmpty)
            recording.emit(terminal)
            let completed = await TestSupport.eventuallyAsync {
                await MainActor.run { expected.completedIDs == [meeting.id] && notifications.count == 3 }
            }
            #expect(completed)
            #expect(!workflow.isBusy)
            #expect(published == [.recording(startedAt: now, folderName: "session-folder"), .processing, terminal])
            #expect(notifications.last?.0 == .processing)
            #expect(notifications.last?.1 == terminal)
            recording.emit(.processing)
            recording.emit(.idle)
            let notified = await TestSupport.eventuallyAsync {
                await MainActor.run { notifications.count == 5 }
            }
            #expect(notified)
            #expect(expected.completedIDs == [meeting.id])
        }

        @Test func failedStartDoesNotLinkOrCompleteAnExpectedMeeting() async {
            let expected = ExpectedMeetingsStub()
            let recording = MeetingRecordingStub()
            recording.startFails = true
            let meeting = makeMeeting()
            expected.value = meeting
            let workflow = makeWorkflow(recording, expected)
            await workflow.observeRecording()
            workflow.startExpectedMeeting(id: meeting.id)
            let failed = await TestSupport.eventuallyAsync {
                await MainActor.run { workflow.phase == .failed("capture unavailable") }
            }
            #expect(failed)
            recording.emit(.processing)
            recording.emit(.idle)
            #expect(expected.recordedIDs.isEmpty)
            #expect(expected.completedIDs.isEmpty)
        }

        @Test(arguments: [ExpectedMeetingStatus.skipped, .cancelled, .completed, .recording])
        func nonScheduledMeetingsDoNotStart(status: ExpectedMeetingStatus) async {
            let expected = ExpectedMeetingsStub()
            let recording = MeetingRecordingStub()
            let meeting = makeMeeting(status: status)
            expected.value = meeting
            let workflow = makeWorkflow(recording, expected)
            workflow.startExpectedMeeting(id: meeting.id)
            let lookedUp = await TestSupport.eventuallyAsync {
                await MainActor.run { expected.lookupIDs == [meeting.id] }
            }
            #expect(lookedUp)
            #expect(recording.startedIDs.isEmpty)
            #expect(expected.recordedIDs.isEmpty)
        }

        @Test func expiredMeetingDoesNotStart() async {
            let expected = ExpectedMeetingsStub()
            let recording = MeetingRecordingStub()
            var meeting = makeMeeting()
            meeting.scheduledEndAt = now
            expected.value = meeting
            let workflow = makeWorkflow(recording, expected)
            workflow.startExpectedMeeting(id: meeting.id)
            let lookedUp = await TestSupport.eventuallyAsync {
                await MainActor.run { expected.lookupIDs == [meeting.id] }
            }
            #expect(lookedUp)
            #expect(recording.startedIDs.isEmpty)
        }

        @Test func busyWorkflowRejectsReminderBeforeLookup() async {
            let expected = ExpectedMeetingsStub()
            let recording = MeetingRecordingStub()
            let workflow = makeWorkflow(recording, expected)
            await workflow.observeRecording()
            recording.emit(.processing)
            workflow.startExpectedMeeting(id: UUID())
            #expect(expected.lookupIDs.isEmpty)
            #expect(recording.startedIDs.isEmpty)
        }

        @Test func forwardsReminderAndRecordingCommands() async {
            let expected = ExpectedMeetingsStub()
            let recording = MeetingRecordingStub()
            let workflow = makeWorkflow(recording, expected)
            let id = UUID()
            workflow.restoreReminders()
            workflow.skipExpectedMeeting(id: id)
            workflow.toggle()
            let forwarded = await TestSupport.eventuallyAsync {
                await MainActor.run {
                    expected.restoreCount == 1 && expected.skippedIDs == [id] && recording.toggleCount == 1
                }
            }
            #expect(forwarded)
        }

        private func makeWorkflow(
            _ recording: MeetingRecordingStub, _ expected: ExpectedMeetingsStub
        ) -> MacMeetingWorkflowController {
            MacMeetingWorkflowController(
                recording: recording, expectedMeetings: expected,
                publishLivePhase: { _ in }, notifyPhase: { _, _ in }, now: { now })
        }

        private func makeMeeting(status: ExpectedMeetingStatus = .scheduled) -> ExpectedMeeting {
            ExpectedMeeting(
                id: UUID(), source: "calendar", externalID: "event", scheduledStartAt: now,
                scheduledEndAt: now.addingTimeInterval(3600), title: "Meeting", attendees: [],
                meetingURL: nil, notes: nil, sourceModifiedAt: nil, status: status, recordedMeetingID: nil)
        }
    }

    @MainActor
    private final class MeetingRecordingStub: MeetingRecordingControlling {
        var phase: MacMeetingRecordingPhase = .idle
        var startedIDs: [UUID] = []
        var toggleCount = 0
        var startFails = false
        private var handler: (@MainActor @Sendable (MacMeetingRecordingPhase) -> Void)?

        @MainActor func setPhaseHandler(_ handler: @escaping @MainActor @Sendable (MacMeetingRecordingPhase) -> Void)
            async
        {
            self.handler = handler
        }
        @MainActor func currentPhase() async -> MacMeetingRecordingPhase { phase }
        @MainActor func start(expectedMeeting: ExpectedMeeting) async {
            startedIDs.append(expectedMeeting.id)
            emit(
                startFails
                    ? .failed("capture unavailable")
                    : .recording(
                        startedAt: expectedMeeting.scheduledStartAt, folderName: "session-folder"))
        }
        @MainActor func toggle() async { toggleCount += 1 }
        @MainActor func emit(_ phase: MacMeetingRecordingPhase) {
            self.phase = phase
            handler?(phase)
        }
    }

    @MainActor
    private final class ExpectedMeetingsStub: ExpectedMeetingServing {
        var value: ExpectedMeeting?
        var lookupIDs: [UUID] = []
        var recordedIDs: [UUID] = []
        var folderNames: [String] = []
        var completedIDs: [UUID] = []
        var skippedIDs: [UUID] = []
        var restoreCount = 0

        @MainActor func meeting(id: UUID) async -> ExpectedMeeting? {
            lookupIDs.append(id)
            return value
        }
        @MainActor func markRecorded(id: UUID, meetingID: String) async throws {
            recordedIDs.append(id)
            folderNames.append(meetingID)
        }
        @MainActor func markCompleted(id: UUID) async throws { completedIDs.append(id) }
        @MainActor func skip(id: UUID) async throws { skippedIDs.append(id) }
        @MainActor func restoreReminders() async { restoreCount += 1 }
        @MainActor func meetings(from startAt: Date, to endAt: Date) async throws -> [ExpectedMeeting] { [] }
        @MainActor func sync(sourceScope: String, windowStart: Date, windowEnd: Date, inputs: [ExpectedMeetingInput])
            async throws
            -> ExpectedMeetingSyncResult
        {
            ExpectedMeetingSyncResult(created: 0, updated: 0, cancelled: 0, meetings: [])
        }
    }
#endif
