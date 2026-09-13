#if os(macOS)
    import Foundation
    import Testing

    @testable import Stet

    @Suite("Calendar Meeting Mapper")
    struct CalendarMeetingMapperTests {
        @Test func mapsIdentityParticipantsAndMeetingLink() throws {
            let event = makeEvent(
                title: " Project sync ",
                location: "Join https://meet.google.com/abc-defg-hij.",
                attendees: [
                    participant(name: "Me", status: .accepted, isCurrentUser: true),
                    participant(name: "Taylor", email: "taylor@example.com"),
                ]
            )

            let input = try #require(CalendarMeetingMapper().map(event))

            #expect(input.source == "calendar:source-1:calendar-1")
            #expect(input.externalID == event.identity.stableID)
            #expect(input.title == "Project sync")
            #expect(input.meetingURL == URL(string: "https://meet.google.com/abc-defg-hij"))
            #expect(input.attendees == [MeetingAttendee(name: "Taylor", email: "taylor@example.com")])
        }

        @Test func normalizesPlaceholderTitles() throws {
            let input = try #require(CalendarMeetingMapper().map(makeEvent(title: " (NO Title) ")))
            #expect(input.title == nil)
        }

        @Test(arguments: [
            makeEvent(isAllDay: true),
            makeEvent(status: .canceled),
            makeEvent(attendees: [participant(name: "Me", status: .declined, isCurrentUser: true)]),
        ])
        func ignoresIneligibleEvents(_ event: CalendarEvent) {
            #expect(CalendarMeetingMapper().map(event) == nil)
        }

        @Test func recurringOccurrencesHaveDistinctStableIDs() {
            let first = makeEvent(originalStart: Date(timeIntervalSince1970: 1_700_000_000))
            let second = makeEvent(originalStart: Date(timeIntervalSince1970: 1_700_086_400))
            #expect(first.identity.stableID != second.identity.stableID)
        }
    }

    private func makeEvent(
        title: String? = "Meeting",
        isAllDay: Bool = false,
        status: CalendarEventStatus = .confirmed,
        location: String? = nil,
        attendees: [CalendarParticipant] = [],
        originalStart: Date? = nil
    ) -> CalendarEvent {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        return CalendarEvent(
            identity: CalendarEventIdentity(
                eventID: "event-1",
                calendarID: "calendar-1",
                sourceID: "source-1",
                occurrence: originalStart.map {
                    CalendarOccurrenceIdentity(occurrenceStart: start, originalStart: $0, isDetached: false)
                }
            ),
            title: title,
            startAt: start,
            endAt: start.addingTimeInterval(1_800),
            isAllDay: isAllDay,
            status: status,
            availability: .busy,
            location: location,
            url: nil,
            notes: nil,
            modifiedAt: nil,
            organizer: nil,
            attendees: attendees
        )
    }

    private func participant(
        name: String?,
        email: String? = nil,
        status: CalendarParticipantStatus = .accepted,
        isCurrentUser: Bool = false
    ) -> CalendarParticipant {
        CalendarParticipant(
            name: name,
            email: email,
            url: email.flatMap { URL(string: "mailto:\($0)") },
            status: status,
            role: .required,
            type: .person,
            isCurrentUser: isCurrentUser
        )
    }
#endif
