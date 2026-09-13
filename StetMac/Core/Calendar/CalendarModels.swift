#if os(macOS)
    import Foundation

    nonisolated enum CalendarAuthorizationStatus: Equatable, Sendable {
        case notDetermined
        case fullAccess
        case writeOnly
        case denied
        case restricted
    }

    nonisolated enum CalendarSourceType: String, Codable, Sendable {
        case local
        case exchange
        case calDAV
        case mobileMe
        case subscribed
        case birthdays
        case unknown
    }

    nonisolated struct CalendarSourceRecord: Codable, Equatable, Hashable, Sendable {
        var id: String
        var title: String
        var type: CalendarSourceType
    }

    nonisolated struct CalendarRecord: Codable, Equatable, Identifiable, Sendable {
        var id: String
        var title: String
        var source: CalendarSourceRecord
        var colorHex: String?
        var isEditable: Bool
        var isSubscribed: Bool
    }

    nonisolated struct CalendarOccurrenceIdentity: Codable, Equatable, Hashable, Sendable {
        var occurrenceStart: Date
        var originalStart: Date
        var isDetached: Bool
    }

    nonisolated struct CalendarEventIdentity: Codable, Equatable, Hashable, Sendable {
        var eventID: String
        var calendarID: String
        var sourceID: String
        var occurrence: CalendarOccurrenceIdentity?

        var stableID: String {
            let components = [
                sourceID,
                calendarID,
                eventID,
                occurrence.map { String($0.originalStart.timeIntervalSinceReferenceDate) } ?? "",
            ]
            return components.joined(separator: "\u{1f}")
        }
    }

    nonisolated enum CalendarEventStatus: String, Codable, Sendable {
        case none
        case tentative
        case confirmed
        case canceled
    }

    nonisolated enum CalendarEventAvailability: String, Codable, Sendable {
        case unknown
        case busy
        case free
        case tentative
        case unavailable
    }

    nonisolated enum CalendarParticipantStatus: String, Codable, Sendable {
        case unknown
        case pending
        case accepted
        case declined
        case tentative
        case delegated
        case completed
        case inProcess = "in_process"
    }

    nonisolated enum CalendarParticipantRole: String, Codable, Sendable {
        case unknown
        case required
        case optional
        case chair
        case nonParticipant = "non_participant"
    }

    nonisolated enum CalendarParticipantType: String, Codable, Sendable {
        case unknown
        case person
        case room
        case resource
        case group
    }

    nonisolated struct CalendarParticipant: Codable, Equatable, Sendable {
        var name: String?
        var email: String?
        var url: URL?
        var status: CalendarParticipantStatus
        var role: CalendarParticipantRole
        var type: CalendarParticipantType
        var isCurrentUser: Bool
    }

    nonisolated struct CalendarStructuredLocation: Codable, Equatable, Sendable {
        var title: String
        var latitude: Double?
        var longitude: Double?
        var radius: Double?
    }

    nonisolated enum CalendarAlarmKind: String, Codable, Sendable { case relative, absolute, proximity }
    nonisolated enum CalendarAlarmAction: String, Codable, Sendable { case display, audio, procedure, email, unknown }
    nonisolated enum CalendarAlarmProximity: String, Codable, Sendable { case enter, leave }

    nonisolated enum CalendarAlarmInput: Equatable, Sendable {
        static let maximumRelativeMinutes = 525_600
        case relative(minutes: Int, emailAddress: String?)
        case absolute(at: Date, emailAddress: String?)
        case proximity(
            proximity: CalendarAlarmProximity,
            locationTitle: String,
            latitude: Double,
            longitude: Double,
            radius: Double,
            emailAddress: String?
        )
    }

    nonisolated struct CalendarAlarm: Codable, Equatable, Sendable {
        var kind: CalendarAlarmKind
        var relativeOffsetMinutes: Double?
        var absoluteAt: Date?
        var proximity: CalendarAlarmProximity?
        var locationTitle: String?
        var latitude: Double?
        var longitude: Double?
        var radius: Double?
        var action: CalendarAlarmAction
        var emailAddress: String?
        var soundName: String?
    }

    nonisolated enum CalendarRecurrenceFrequency: String, Codable, Sendable { case daily, weekly, monthly, yearly }
    nonisolated enum CalendarWeekday: String, Codable, Sendable {
        case sunday, monday, tuesday, wednesday, thursday, friday, saturday
    }
    nonisolated struct CalendarRecurrenceWeekday: Codable, Equatable, Hashable, Sendable {
        var day: CalendarWeekday
        var weekNumber: Int = 0
    }
    nonisolated enum CalendarRecurrenceEnd: Codable, Equatable, Sendable {
        case occurrenceCount(Int)
        case endDate(Date)
    }
    nonisolated struct CalendarRecurrenceRule: Codable, Equatable, Sendable {
        static let maximumInterval = Int(Int32.max)
        var frequency: CalendarRecurrenceFrequency
        var interval: Int = 1
        var daysOfTheWeek: [CalendarRecurrenceWeekday] = []
        var daysOfTheMonth: [Int] = []
        var monthsOfTheYear: [Int] = []
        var weeksOfTheYear: [Int] = []
        var daysOfTheYear: [Int] = []
        var setPositions: [Int] = []
        var firstDayOfTheWeek: CalendarWeekday?
        var end: CalendarRecurrenceEnd?
    }

    nonisolated struct CalendarEvent: Codable, Equatable, Identifiable, Sendable {
        var identity: CalendarEventIdentity
        var title: String?
        var startAt: Date
        var endAt: Date
        var isAllDay: Bool
        var status: CalendarEventStatus
        var availability: CalendarEventAvailability
        var location: String?
        var url: URL?
        var notes: String?
        var structuredLocation: CalendarStructuredLocation? = nil
        var externalID: String? = nil
        var calendarTitle: String = ""
        var timeZoneIdentifier: String? = nil
        var createdAt: Date? = nil
        var modifiedAt: Date?
        var alarms: [CalendarAlarm] = []
        var recurrenceRules: [CalendarRecurrenceRule] = []
        var organizer: CalendarParticipant?
        var attendees: [CalendarParticipant]

        var id: String { identity.stableID }
        var hasAlarms: Bool { !alarms.isEmpty }
        var isRecurring: Bool { !recurrenceRules.isEmpty || identity.occurrence != nil }
    }

    nonisolated struct CalendarEventQuery: Equatable, Sendable {
        static let maximumDuration: TimeInterval = 4 * 366 * 24 * 60 * 60

        var startAt: Date
        var endAt: Date
        var calendarIDs: Set<String>

        init(startAt: Date, endAt: Date, calendarIDs: Set<String>) {
            self.startAt = startAt
            self.endAt = endAt
            self.calendarIDs = calendarIDs
        }
    }

    nonisolated struct CalendarEventCreateRequest: Equatable, Sendable {
        var calendarID: String
        var title: String
        var startAt: Date
        var endAt: Date
        var isAllDay: Bool = false
        var availability: CalendarEventAvailability = .busy
        var location: String?
        var url: URL?
        var notes: String?
        var timeZoneIdentifier: String?
        var alarms: [CalendarAlarmInput] = []
        var recurrenceRules: [CalendarRecurrenceRule] = []
    }

    nonisolated enum CalendarFieldUpdate<Value>: Equatable, Sendable
    where Value: Equatable & Sendable {
        case unchanged
        case set(Value)
        case clear
    }

    nonisolated struct CalendarEventUpdateRequest: Equatable, Sendable {
        var title: String?
        var startAt: Date?
        var endAt: Date?
        var calendarID: String?
        var isAllDay: Bool?
        var availability: CalendarEventAvailability?
        var location: CalendarFieldUpdate<String> = .unchanged
        var url: CalendarFieldUpdate<URL> = .unchanged
        var notes: CalendarFieldUpdate<String> = .unchanged
        var timeZoneIdentifier: CalendarFieldUpdate<String> = .unchanged
        var alarms: [CalendarAlarmInput]?
        var recurrenceRules: [CalendarRecurrenceRule]?

        var hasChanges: Bool {
            title != nil || startAt != nil || endAt != nil || calendarID != nil || isAllDay != nil
                || availability != nil || location != .unchanged || url != .unchanged || notes != .unchanged
                || timeZoneIdentifier != .unchanged || alarms != nil || recurrenceRules != nil
        }
    }

    nonisolated enum CalendarEventMutationSpan: Sendable {
        case thisEvent
        case futureEvents
    }

    nonisolated struct CalendarBusyWindow: Equatable, Sendable {
        var startAt: Date
        var endAt: Date
        var eventIDs: [String]
    }

    nonisolated enum CalendarClientError: LocalizedError, Equatable, Sendable {
        case accessNotGranted(CalendarAuthorizationStatus)
        case invalidRange
        case rangeTooLarge
        case calendarNotFound(String)
        case calendarNotWritable(String)
        case calendarNotAllowed(String)
        case eventNotFound(CalendarEventIdentity)
        case ambiguousCalendarTitle(String, [String])
        case defaultCalendarUnavailable
        case invalidInput(String)

        var errorDescription: String? {
            switch self {
            case .accessNotGranted(let status):
                "Calendar full access is required; current status is \(status)."
            case .invalidRange:
                "Calendar query end must be after its start."
            case .rangeTooLarge:
                "Calendar queries cannot span more than four years."
            case .calendarNotFound(let id):
                "No calendar matches ID '\(id)'."
            case .calendarNotWritable(let id):
                "Calendar '\(id)' does not allow modifications."
            case .calendarNotAllowed(let id):
                "Calendar '\(id)' is not selected in Stet settings."
            case .eventNotFound(let identity):
                "Calendar event '\(identity.stableID)' was not found."
            case .ambiguousCalendarTitle(let title, let ids):
                "Calendar title '\(title)' is ambiguous; matching IDs: \(ids.joined(separator: ", "))."
            case .defaultCalendarUnavailable:
                "No writable default selected calendar is available."
            case .invalidInput(let message):
                message
            }
        }
    }
#endif
