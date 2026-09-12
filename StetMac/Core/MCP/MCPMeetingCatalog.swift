#if os(macOS)
    import Foundation

    enum MCPMeetingStatus: String, Codable, Sendable {
        case recording
        case processing
        case ready
        case organized
        case failed
    }

    struct MCPMeetingSummary: Codable, Equatable, Sendable {
        let id: String
        let startedAt: String
        let endedAt: String?
        let durationSeconds: Double
        let status: String
        let speakerCount: Int
        let failureMessage: String?
        let metadata: MCPMeetingMetadata?

        private enum CodingKeys: String, CodingKey {
            case id
            case startedAt = "started_at"
            case endedAt = "ended_at"
            case durationSeconds = "duration_seconds"
            case status
            case speakerCount = "speaker_count"
            case failureMessage = "failure_message"
            case metadata
        }
    }

    struct MCPMeetingListOutput: Codable, Equatable, Sendable {
        let meetings: [MCPMeetingSummary]
    }

    struct MCPMeetingTranscriptOutput: Codable, Equatable, Sendable {
        let id: String
        let startedAt: String
        let endedAt: String?
        let durationSeconds: Double
        let status: String
        let speakerCount: Int
        let transcript: String?
        let failureMessage: String?
        let metadata: MCPMeetingMetadata?

        private enum CodingKeys: String, CodingKey {
            case id
            case startedAt = "started_at"
            case endedAt = "ended_at"
            case durationSeconds = "duration_seconds"
            case status
            case speakerCount = "speaker_count"
            case transcript
            case failureMessage = "failure_message"
            case metadata
        }
    }

    struct MCPMeetingMetadata: Codable, Equatable, Sendable {
        let expectedMeetingID: UUID?
        let source: String?
        let externalID: String?
        let title: String?
        let scheduledStartAt: String?
        let scheduledEndAt: String?
        let attendees: [MeetingAttendee]
        let meetingURL: URL?

        init(_ metadata: MeetingMetadata) {
            self.expectedMeetingID = metadata.expectedMeetingID
            self.source = metadata.source
            self.externalID = metadata.externalID
            self.title = metadata.title
            self.scheduledStartAt = metadata.scheduledStartAt.map(Self.iso8601String)
            self.scheduledEndAt = metadata.scheduledEndAt.map(Self.iso8601String)
            self.attendees = metadata.attendees
            self.meetingURL = metadata.meetingURL
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

        private nonisolated static func iso8601String(_ date: Date) -> String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.string(from: date)
        }
    }

    enum MCPMeetingError: LocalizedError, Equatable, Sendable {
        case meetingNotFound(String)
        case noReadyMeeting
        case invalidLimit

        var errorDescription: String? {
            switch self {
            case .meetingNotFound(let id):
                return "No meeting found with id \(id)."
            case .noReadyMeeting:
                return "No unorganized meeting transcript is available."
            case .invalidLimit:
                return "limit must be an integer of at least 1."
            }
        }
    }

    nonisolated protocol MCPMeetingServing: Sendable {
        func listMeetings(limit: Int) throws -> MCPMeetingListOutput
        func listUnorganizedMeetings(limit: Int) throws -> MCPMeetingListOutput
        func meetingTranscript(meetingID: String?) throws -> MCPMeetingTranscriptOutput
    }

    final class MCPLiveMeetingPhaseStore: @unchecked Sendable {
        private let lock = NSLock()
        private var phase: MacMeetingRecordingPhase = .idle

        func update(_ phase: MacMeetingRecordingPhase) {
            lock.lock()
            defer { lock.unlock() }
            self.phase = phase
        }

        func current() -> MacMeetingRecordingPhase {
            lock.lock()
            defer { lock.unlock() }
            return phase
        }
    }

    struct MCPMeetingCatalog: MCPMeetingServing {
        static let defaultLimit = 20
        static let maxLimit = 100

        private let store: MeetingRecordingStore
        private let livePhase: @Sendable () -> MacMeetingRecordingPhase
        private let now: @Sendable () -> Date

        init(
            store: MeetingRecordingStore,
            livePhase: @escaping @Sendable () -> MacMeetingRecordingPhase = { .idle },
            now: @escaping @Sendable () -> Date = Date.init
        ) {
            self.store = store
            self.livePhase = livePhase
            self.now = now
        }

        func listMeetings(limit: Int) throws -> MCPMeetingListOutput {
            MCPMeetingListOutput(meetings: Array(try loadMeetings().prefix(limit)).map(\.summary))
        }

        func listUnorganizedMeetings(limit: Int) throws -> MCPMeetingListOutput {
            let meetings = try loadMeetings().filter { $0.status == .ready }
            return MCPMeetingListOutput(meetings: Array(meetings.prefix(limit)).map(\.summary))
        }

        func meetingTranscript(meetingID: String?) throws -> MCPMeetingTranscriptOutput {
            let meetings = try loadMeetings()
            let trimmedID = meetingID?.trimmingCharacters(in: .whitespacesAndNewlines)
            let meeting: ResolvedMeeting
            if let trimmedID, !trimmedID.isEmpty {
                guard let found = meetings.first(where: { $0.id == trimmedID }) else {
                    throw MCPMeetingError.meetingNotFound(trimmedID)
                }
                meeting = found
            } else if let found = meetings.first(where: { $0.status == .ready }) {
                meeting = found
            } else {
                throw MCPMeetingError.noReadyMeeting
            }

            let transcript = try store.transcriptText(for: meeting.directory)
            return meeting.transcriptOutput(transcript: transcript)
        }

        static func resolvedLimit(_ raw: Int?) throws -> Int {
            guard let raw else { return defaultLimit }
            guard raw >= 1 else { throw MCPMeetingError.invalidLimit }
            return min(raw, maxLimit)
        }

        private func loadMeetings() throws -> [ResolvedMeeting] {
            let overlay = livePhase()
            return try store.sessionDirectories().compactMap { url in
                resolvedMeeting(url: url, overlay: overlay)
            }
            .sorted { $0.startedAt > $1.startedAt }
        }

        private func resolvedMeeting(
            url: URL,
            overlay: MacMeetingRecordingPhase
        ) -> ResolvedMeeting? {
            let id = url.lastPathComponent
            guard let directory = store.sessionDirectory(id: id) else { return nil }
            let record = try? store.record(for: directory)
            let startedAt = record?.startedAt ?? directory.startedAt
            let status = Self.status(id: id, record: record, overlay: overlay)
            let durationSeconds: Double
            if let record {
                durationSeconds = record.durationSeconds
            } else {
                durationSeconds = max(0, now().timeIntervalSince(startedAt))
            }
            return ResolvedMeeting(
                id: id,
                startedAt: startedAt,
                endedAt: record?.endedAt,
                durationSeconds: durationSeconds,
                status: status,
                speakerCount: record?.speakerCount ?? 0,
                failureMessage: record?.failureMessage,
                metadata: record?.metadata.map { MCPMeetingMetadata($0) },
                directory: directory
            )
        }

        private nonisolated static func status(
            id: String,
            record: MeetingSessionRecord?,
            overlay: MacMeetingRecordingPhase
        ) -> MCPMeetingStatus {
            switch overlay {
            case .recording(_, let folderName) where folderName == id:
                return .recording
            case .processing:
                if record == nil { return .processing }
            default:
                break
            }

            guard let record else { return .processing }
            if record.status == "failed" {
                return .failed
            }
            if record.organizedAt != nil {
                return .organized
            }
            return .ready
        }
    }

    private struct ResolvedMeeting {
        let id: String
        let startedAt: Date
        let endedAt: Date?
        let durationSeconds: Double
        let status: MCPMeetingStatus
        let speakerCount: Int
        let failureMessage: String?
        let metadata: MCPMeetingMetadata?
        let directory: MeetingSessionDirectory

        var summary: MCPMeetingSummary {
            MCPMeetingSummary(
                id: id,
                startedAt: Self.iso8601String(startedAt),
                endedAt: endedAt.map(Self.iso8601String),
                durationSeconds: durationSeconds,
                status: status.rawValue,
                speakerCount: speakerCount,
                failureMessage: failureMessage,
                metadata: metadata
            )
        }

        func transcriptOutput(transcript: String?) -> MCPMeetingTranscriptOutput {
            MCPMeetingTranscriptOutput(
                id: id,
                startedAt: Self.iso8601String(startedAt),
                endedAt: endedAt.map(Self.iso8601String),
                durationSeconds: durationSeconds,
                status: status.rawValue,
                speakerCount: speakerCount,
                transcript: transcript,
                failureMessage: failureMessage,
                metadata: metadata
            )
        }

        private nonisolated static func iso8601String(_ date: Date) -> String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.string(from: date)
        }
    }
#endif
