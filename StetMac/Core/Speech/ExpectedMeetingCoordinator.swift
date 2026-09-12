#if os(macOS)
    import Foundation

    struct ExpectedMeetingInput: Codable, Equatable, Sendable {
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

        private enum CodingKeys: String, CodingKey {
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
        }
    }

    struct ExpectedMeetingSyncResult: Codable, Equatable, Sendable {
        var created: Int
        var updated: Int
        var cancelled: Int
        var meetings: [ExpectedMeeting]
    }

    nonisolated protocol ExpectedMeetingReminderScheduling: Sendable {
        func schedule(_ meeting: ExpectedMeeting) async
        func cancel(_ meeting: ExpectedMeeting) async
    }

    nonisolated protocol ExpectedMeetingServing: Sendable {
        func sync(
            windowStart: Date,
            windowEnd: Date,
            inputs: [ExpectedMeetingInput]
        ) async throws -> ExpectedMeetingSyncResult
        func meeting(id: UUID) async -> ExpectedMeeting?
        func skip(id: UUID) async throws
        func markRecorded(id: UUID, meetingID: String) async throws
        func markCompleted(id: UUID) async throws
        func restoreReminders() async
    }

    enum ExpectedMeetingError: LocalizedError, Equatable, Sendable {
        case invalidWindow
        case invalidMeeting(String)
        case meetingNotFound(UUID)

        var errorDescription: String? {
            switch self {
            case .invalidWindow:
                "window_end must be after window_start."
            case .invalidMeeting(let message):
                message
            case .meetingNotFound(let id):
                "No expected meeting found with id \(id.uuidString)."
            }
        }
    }

    actor ExpectedMeetingCoordinator: ExpectedMeetingServing {
        private let store: ExpectedMeetingStore
        private let reminders: any ExpectedMeetingReminderScheduling
        private let now: @Sendable () -> Date
        private var meetings: [ExpectedMeeting]

        init(
            store: ExpectedMeetingStore = ExpectedMeetingStore(),
            reminders: any ExpectedMeetingReminderScheduling,
            now: @escaping @Sendable () -> Date = Date.init
        ) {
            self.store = store
            self.reminders = reminders
            self.now = now
            self.meetings = (try? store.load()) ?? []
        }

        func sync(
            windowStart: Date,
            windowEnd: Date,
            inputs: [ExpectedMeetingInput]
        ) async throws -> ExpectedMeetingSyncResult {
            guard windowEnd > windowStart else { throw ExpectedMeetingError.invalidWindow }
            var keys = Set<String>()
            for input in inputs {
                guard input.scheduledEndAt > input.scheduledStartAt else {
                    throw ExpectedMeetingError.invalidMeeting(
                        "scheduled_end_at must be after scheduled_start_at for \(input.externalID)."
                    )
                }
                guard input.scheduledStartAt >= windowStart, input.scheduledStartAt < windowEnd else {
                    throw ExpectedMeetingError.invalidMeeting(
                        "Meeting \(input.externalID) is outside the synchronization window."
                    )
                }
                let key = Self.key(source: input.source, externalID: input.externalID)
                guard keys.insert(key).inserted else {
                    throw ExpectedMeetingError.invalidMeeting("Duplicate meeting \(input.externalID).")
                }
            }

            var created = 0
            var updated = 0
            var cancelled = 0
            for input in inputs {
                let index = meetings.firstIndex {
                    $0.source == input.source && $0.externalID == input.externalID
                }
                if let index {
                    let existing = meetings[index]
                    var replacement = ExpectedMeeting(
                        id: existing.id,
                        source: input.source,
                        externalID: input.externalID,
                        scheduledStartAt: input.scheduledStartAt,
                        scheduledEndAt: input.scheduledEndAt,
                        title: input.title,
                        attendees: input.attendees,
                        meetingURL: input.meetingURL,
                        notes: input.notes,
                        sourceModifiedAt: input.sourceModifiedAt,
                        status: input.status,
                        recordedMeetingID: existing.recordedMeetingID
                    )
                    if existing.status == .recording || existing.status == .completed {
                        replacement.status = existing.status
                    }
                    if existing.status == .skipped && input.status == .scheduled {
                        replacement.status = .skipped
                    }
                    if replacement != existing {
                        await reminders.cancel(existing)
                        meetings[index] = replacement
                        updated += 1
                    }
                } else {
                    meetings.append(
                        ExpectedMeeting(
                            id: UUID(),
                            source: input.source,
                            externalID: input.externalID,
                            scheduledStartAt: input.scheduledStartAt,
                            scheduledEndAt: input.scheduledEndAt,
                            title: input.title,
                            attendees: input.attendees,
                            meetingURL: input.meetingURL,
                            notes: input.notes,
                            sourceModifiedAt: input.sourceModifiedAt,
                            status: input.status,
                            recordedMeetingID: nil
                        )
                    )
                    created += 1
                }
            }

            for index in meetings.indices
            where meetings[index].scheduledStartAt >= windowStart
                && meetings[index].scheduledStartAt < windowEnd
                && meetings[index].status == .scheduled
                && !keys.contains(Self.key(source: meetings[index].source, externalID: meetings[index].externalID))
            {
                meetings[index].status = .cancelled
                await reminders.cancel(meetings[index])
                cancelled += 1
            }

            meetings.sort { $0.scheduledStartAt < $1.scheduledStartAt }
            try store.save(meetings)
            for meeting in meetings where meeting.status == .scheduled && meeting.scheduledEndAt > now() {
                await reminders.schedule(meeting)
            }
            return ExpectedMeetingSyncResult(
                created: created,
                updated: updated,
                cancelled: cancelled,
                meetings: meetings.filter {
                    $0.scheduledStartAt >= windowStart && $0.scheduledStartAt < windowEnd
                }
            )
        }

        func meeting(id: UUID) -> ExpectedMeeting? {
            meetings.first { $0.id == id }
        }

        func skip(id: UUID) async throws {
            guard let index = meetings.firstIndex(where: { $0.id == id }) else {
                throw ExpectedMeetingError.meetingNotFound(id)
            }
            meetings[index].status = .skipped
            await reminders.cancel(meetings[index])
            try store.save(meetings)
        }

        func markRecorded(id: UUID, meetingID: String) async throws {
            guard let index = meetings.firstIndex(where: { $0.id == id }) else {
                throw ExpectedMeetingError.meetingNotFound(id)
            }
            meetings[index].status = .recording
            meetings[index].recordedMeetingID = meetingID
            await reminders.cancel(meetings[index])
            try store.save(meetings)
        }

        func markCompleted(id: UUID) throws {
            guard let index = meetings.firstIndex(where: { $0.id == id }) else {
                throw ExpectedMeetingError.meetingNotFound(id)
            }
            meetings[index].status = .completed
            try store.save(meetings)
        }

        func restoreReminders() async {
            for meeting in meetings where meeting.status == .scheduled && meeting.scheduledEndAt > now() {
                await reminders.schedule(meeting)
            }
        }

        private nonisolated static func key(source: String, externalID: String) -> String {
            "\(source)\u{0}\(externalID)"
        }
    }
#endif
