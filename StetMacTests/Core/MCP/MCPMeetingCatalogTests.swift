#if os(macOS)
    import Foundation
    import Testing

    @testable import Stet

    @Suite("MCP Meeting Catalog")
    struct MCPMeetingCatalogTests {
        @Test func listsAllMeetingsAndFiltersUnorganized() throws {
            let root = TestSupport.temporaryDirectoryURL()
            let store = MeetingRecordingStore(rootDirectory: root)
            let older = Date(timeIntervalSince1970: 1_704_067_200)
            let newer = Date(timeIntervalSince1970: 1_704_070_800)
            let organized = Date(timeIntervalSince1970: 1_704_074_400)
            let olderID = try writeMeeting(
                store: store,
                startedAt: older,
                status: "completed",
                transcript: "# older ready"
            )
            let newerID = try writeMeeting(
                store: store,
                startedAt: newer,
                status: "completed",
                transcript: "# newer ready"
            )
            let organizedID = try writeMeeting(
                store: store,
                startedAt: organized,
                status: "completed",
                transcript: "# already organized",
                organizedAt: organized.addingTimeInterval(30)
            )
            _ = try writeMeeting(
                store: store,
                startedAt: Date(timeIntervalSince1970: 1_704_078_000),
                status: "failed",
                transcript: "Processing failed",
                failureMessage: "diarizer exploded",
                speakerCount: 0
            )
            let catalog = MCPMeetingCatalog(store: store)

            let all = try catalog.listMeetings(limit: 20)
            #expect(
                all.meetings.map(\.id) == [
                    MeetingRecordingStore.folderName(for: Date(timeIntervalSince1970: 1_704_078_000)),
                    organizedID,
                    newerID,
                    olderID,
                ])
            #expect(all.meetings.map(\.status) == ["failed", "organized", "ready", "ready"])
            #expect(all.meetings.first?.failureMessage == "diarizer exploded")

            let inbox = try catalog.listUnorganizedMeetings(limit: 20)
            #expect(inbox.meetings.map(\.id) == [newerID, olderID])
            #expect(inbox.meetings.allSatisfy { $0.status == "ready" })

            let limited = try catalog.listUnorganizedMeetings(limit: 1)
            #expect(limited.meetings.map(\.id) == [newerID])
        }

        @Test func getTranscriptReturnsSavedMarkdownAndDefaultsToLatestReady() throws {
            let root = TestSupport.temporaryDirectoryURL()
            let store = MeetingRecordingStore(rootDirectory: root)
            let older = Date(timeIntervalSince1970: 1_704_067_200)
            let newer = Date(timeIntervalSince1970: 1_704_070_800)
            let olderID = try writeMeeting(
                store: store,
                startedAt: older,
                status: "completed",
                transcript: "older transcript"
            )
            let newerID = try writeMeeting(
                store: store,
                startedAt: newer,
                status: "completed",
                transcript: "newer transcript"
            )
            let catalog = MCPMeetingCatalog(store: store)

            let byID = try catalog.meetingTranscript(meetingID: olderID)
            #expect(byID.id == olderID)
            #expect(byID.status == "ready")
            #expect(byID.transcript == "older transcript")
            #expect(byID.speakerCount == 1)

            let latestReady = try catalog.meetingTranscript(meetingID: nil)
            #expect(latestReady.id == newerID)
            #expect(latestReady.transcript == "newer transcript")
        }

        @Test func getTranscriptReportsMissingAndEmptyInbox() throws {
            let root = TestSupport.temporaryDirectoryURL()
            let store = MeetingRecordingStore(rootDirectory: root)
            let catalog = MCPMeetingCatalog(store: store)

            #expect(throws: MCPMeetingError.noReadyMeeting) {
                try catalog.meetingTranscript(meetingID: nil)
            }
            #expect(throws: MCPMeetingError.meetingNotFound("missing")) {
                try catalog.meetingTranscript(meetingID: "missing")
            }
        }

        @Test func overlaysLiveRecordingAndProcessing() throws {
            let root = TestSupport.temporaryDirectoryURL()
            let store = MeetingRecordingStore(rootDirectory: root)
            let startedAt = Date(timeIntervalSince1970: 1_704_067_200)
            let directory = try store.makeSessionDirectory(startedAt: startedAt)
            let id = directory.url.lastPathComponent
            let now = startedAt.addingTimeInterval(90)
            let catalog = MCPMeetingCatalog(
                store: store,
                livePhase: {
                    .recording(startedAt: startedAt, folderName: id)
                },
                now: { now }
            )

            let recording = try catalog.listMeetings(limit: 20)
            #expect(recording.meetings.count == 1)
            #expect(recording.meetings.first?.id == id)
            #expect(recording.meetings.first?.status == "recording")
            #expect(recording.meetings.first?.durationSeconds == 90)
            #expect(try catalog.listUnorganizedMeetings(limit: 20).meetings.isEmpty)

            let processingCatalog = MCPMeetingCatalog(
                store: store,
                livePhase: { .processing }
            )
            let processing = try processingCatalog.listMeetings(limit: 20)
            #expect(processing.meetings.first?.status == "processing")

            let orphanCatalog = MCPMeetingCatalog(store: store)
            #expect(try orphanCatalog.listMeetings(limit: 20).meetings.first?.status == "processing")
        }

        @Test func getTranscriptOnInProgressMeetingOmitsBody() throws {
            let root = TestSupport.temporaryDirectoryURL()
            let store = MeetingRecordingStore(rootDirectory: root)
            let startedAt = Date(timeIntervalSince1970: 1_704_067_200)
            let directory = try store.makeSessionDirectory(startedAt: startedAt)
            let id = directory.url.lastPathComponent
            let catalog = MCPMeetingCatalog(
                store: store,
                livePhase: { .recording(startedAt: startedAt, folderName: id) }
            )

            let output = try catalog.meetingTranscript(meetingID: id)
            #expect(output.status == "recording")
            #expect(output.transcript == nil)
        }

        @Test func resolvedLimitClampsAndRejectsInvalidValues() throws {
            #expect(try MCPMeetingCatalog.resolvedLimit(nil) == 20)
            #expect(try MCPMeetingCatalog.resolvedLimit(1) == 1)
            #expect(try MCPMeetingCatalog.resolvedLimit(500) == 100)
            #expect(throws: MCPMeetingError.invalidLimit) {
                try MCPMeetingCatalog.resolvedLimit(0)
            }
        }
    }

    private func writeMeeting(
        store: MeetingRecordingStore,
        startedAt: Date,
        status: String,
        transcript: String,
        organizedAt: Date? = nil,
        failureMessage: String? = nil,
        speakerCount: Int = 1
    ) throws -> String {
        let directory = try store.makeSessionDirectory(startedAt: startedAt)
        let endedAt = startedAt.addingTimeInterval(60)
        try transcript.write(to: directory.transcriptURL, atomically: true, encoding: .utf8)
        let record = MeetingSessionRecord(
            startedAt: startedAt,
            endedAt: endedAt,
            durationSeconds: endedAt.timeIntervalSince(startedAt),
            status: status,
            failureMessage: failureMessage,
            speakerCount: speakerCount,
            organizedAt: organizedAt
        )
        try record.jsonData().write(to: directory.sessionURL)
        return directory.url.lastPathComponent
    }
#endif
