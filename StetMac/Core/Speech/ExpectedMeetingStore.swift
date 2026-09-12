#if os(macOS)
    import Foundation

    struct MeetingAttendee: Codable, Equatable, Sendable {
        var name: String
        var email: String?
    }

    enum ExpectedMeetingStatus: String, Codable, Sendable {
        case scheduled
        case recording
        case skipped
        case cancelled
        case completed
    }

    struct ExpectedMeeting: Codable, Equatable, Identifiable, Sendable {
        var id: UUID
        var source: String
        var externalID: String
        var scheduledStartAt: Date
        var scheduledEndAt: Date
        var title: String?
        var attendees: [MeetingAttendee]
        var meetingURL: URL?
        var notes: String?
        var sourceModifiedAt: Date?
        var status: ExpectedMeetingStatus
        var recordedMeetingID: String?

        var reminderIdentifier: String {
            "stet.expected-meeting.\(id.uuidString)"
        }

        private enum CodingKeys: String, CodingKey {
            case id
            case source
            case externalID = "external_id"
            case scheduledStartAt = "scheduled_start_at"
            case scheduledEndAt = "scheduled_end_at"
            case title
            case attendees
            case meetingURL = "meeting_url"
            case notes
            case sourceModifiedAt = "source_modified_at"
            case status
            case recordedMeetingID = "recorded_meeting_id"
        }
    }

    struct MeetingMetadata: Codable, Equatable, Sendable {
        var expectedMeetingID: UUID?
        var source: String?
        var externalID: String?
        var title: String?
        var scheduledStartAt: Date?
        var scheduledEndAt: Date?
        var attendees: [MeetingAttendee]
        var meetingURL: URL?

        init(expectedMeeting: ExpectedMeeting) {
            self.expectedMeetingID = expectedMeeting.id
            self.source = expectedMeeting.source
            self.externalID = expectedMeeting.externalID
            self.title = expectedMeeting.title
            self.scheduledStartAt = expectedMeeting.scheduledStartAt
            self.scheduledEndAt = expectedMeeting.scheduledEndAt
            self.attendees = expectedMeeting.attendees
            self.meetingURL = expectedMeeting.meetingURL
        }

        private enum CodingKeys: String, CodingKey {
            case expectedMeetingID = "expected_meeting_id"
            case source
            case externalID = "external_id"
            case title
            case scheduledStartAt = "scheduled_start_at"
            case scheduledEndAt = "scheduled_end_at"
            case attendees
            case meetingURL = "meeting_url"
        }
    }

    struct ExpectedMeetingStore: Sendable {
        let fileURL: URL
        private let fileManager: FileManager

        init(fileManager: FileManager = .default, fileURL: URL? = nil) {
            self.fileManager = fileManager
            self.fileURL =
                fileURL
                ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("Stet", isDirectory: true)
                .appendingPathComponent("expected-meetings.json")
        }

        func load() throws -> [ExpectedMeeting] {
            guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([ExpectedMeeting].self, from: Data(contentsOf: fileURL))
        }

        func save(_ meetings: [ExpectedMeeting]) throws {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(meetings).write(to: fileURL, options: .atomic)
        }
    }
#endif
