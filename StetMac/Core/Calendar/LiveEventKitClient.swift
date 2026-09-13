#if os(macOS)
    import AppKit
    import CoreLocation
    import EventKit
    import Foundation

    @MainActor
    final class LiveEventKitClient: CalendarWriteClient {
        private let store: EKEventStore

        init(store: EKEventStore = EKEventStore()) {
            self.store = store
        }

        func authorizationStatus() -> CalendarAuthorizationStatus {
            switch EKEventStore.authorizationStatus(for: .event) {
            case .notDetermined: .notDetermined
            case .fullAccess: .fullAccess
            case .writeOnly: .writeOnly
            case .denied: .denied
            case .restricted: .restricted
            @unknown default: .denied
            }
        }

        func requestFullAccess() async throws -> Bool {
            let application = NSApplication.shared
            let previousPolicy = application.activationPolicy()
            if previousPolicy == .prohibited {
                application.setActivationPolicy(.regular)
            }
            application.activate(ignoringOtherApps: true)
            defer {
                if previousPolicy == .prohibited {
                    application.setActivationPolicy(previousPolicy)
                }
            }
            return try await store.requestFullAccessToEvents()
        }

        func changes() -> AsyncStream<Void> {
            AsyncStream { continuation in
                let token = NotificationCenter.default.addObserver(
                    forName: .EKEventStoreChanged,
                    object: store,
                    queue: .main
                ) { _ in
                    continuation.yield()
                }
                continuation.onTermination = { _ in
                    NotificationCenter.default.removeObserver(token)
                }
            }
        }

        func calendars() throws -> [CalendarRecord] {
            try requireAccess()
            return store.calendars(for: .event)
                .map(Self.mapCalendar)
                .sorted {
                    let comparison = $0.title.localizedCaseInsensitiveCompare($1.title)
                    return comparison == .orderedSame ? $0.id < $1.id : comparison == .orderedAscending
                }
        }

        func defaultCalendarID() throws -> String? {
            try requireAccess()
            return store.defaultCalendarForNewEvents?.calendarIdentifier
        }

        func events(matching query: CalendarEventQuery) throws -> [CalendarEvent] {
            try requireAccess()
            try validate(query)
            if query.calendarIDs.isEmpty { return [] }
            let selected = try query.calendarIDs.map(resolveCalendar)
            let predicate = store.predicateForEvents(
                withStart: query.startAt,
                end: query.endAt,
                calendars: selected
            )
            return store.events(matching: predicate)
                .map(Self.mapEvent)
                .sorted {
                    $0.startAt == $1.startAt ? $0.id < $1.id : $0.startAt < $1.startAt
                }
        }

        func event(_ identity: CalendarEventIdentity) throws -> CalendarEvent {
            try requireAccess()
            return Self.mapEvent(try resolveEvent(identity))
        }

        func create(_ request: CalendarEventCreateRequest) throws -> CalendarEvent {
            try requireAccess()
            let calendar = try resolveWritableCalendar(request.calendarID)
            let range = try normalizedRange(
                start: request.startAt,
                end: request.endAt,
                isAllDay: request.isAllDay,
                timeZone: try resolveTimeZone(request.timeZoneIdentifier) ?? .current
            )
            let event = EKEvent(eventStore: store)
            event.calendar = calendar
            event.title = request.title
            event.startDate = range.start
            event.endDate = range.end
            event.isAllDay = request.isAllDay
            event.availability = request.availability.eventKitValue
            event.location = request.location
            event.url = request.url
            event.notes = request.notes
            event.timeZone = try resolveTimeZone(request.timeZoneIdentifier)
            event.alarms = try request.alarms.map(makeAlarm)
            try validateRecurrences(request.recurrenceRules, start: range.start)
            event.recurrenceRules = try request.recurrenceRules.map(makeRecurrence)
            try store.save(event, span: .thisEvent)
            return Self.mapEvent(event)
        }

        func update(
            _ identity: CalendarEventIdentity,
            with request: CalendarEventUpdateRequest,
            span: CalendarEventMutationSpan
        ) throws -> CalendarEvent {
            try requireAccess()
            guard request.hasChanges else {
                throw CalendarClientError.invalidInput("At least one event field must be updated.")
            }
            let event = try resolveEvent(identity)
            guard event.calendar.allowsContentModifications else {
                throw CalendarClientError.calendarNotWritable(event.calendar.calendarIdentifier)
            }
            if let title = request.title { event.title = title }
            if let startAt = request.startAt { event.startDate = startAt }
            if let endAt = request.endAt { event.endDate = endAt }
            if let calendarID = request.calendarID { event.calendar = try resolveWritableCalendar(calendarID) }
            if let isAllDay = request.isAllDay { event.isAllDay = isAllDay }
            if let availability = request.availability { event.availability = availability.eventKitValue }
            apply(request.location, to: &event.location)
            apply(request.url, to: &event.url)
            apply(request.notes, to: &event.notes)
            switch request.timeZoneIdentifier {
            case .unchanged: break
            case .clear: event.timeZone = nil
            case .set(let identifier): event.timeZone = try resolveTimeZone(identifier)
            }
            let range = try normalizedRange(
                start: event.startDate,
                end: event.endDate,
                isAllDay: event.isAllDay,
                timeZone: event.timeZone ?? .current
            )
            event.startDate = range.start
            event.endDate = range.end
            if let alarms = request.alarms { event.alarms = try alarms.map(makeAlarm) }
            if let recurrenceRules = request.recurrenceRules {
                try validateRecurrences(recurrenceRules, start: range.start)
                event.recurrenceRules = try recurrenceRules.map(makeRecurrence)
            }
            try store.save(event, span: span.eventKitValue)
            return Self.mapEvent(event)
        }

        func delete(_ identity: CalendarEventIdentity, span: CalendarEventMutationSpan) throws {
            try requireAccess()
            let event = try resolveEvent(identity)
            guard event.calendar.allowsContentModifications else {
                throw CalendarClientError.calendarNotWritable(event.calendar.calendarIdentifier)
            }
            try store.remove(event, span: span.eventKitValue)
        }

        func freeBusy(matching query: CalendarEventQuery) throws -> [CalendarBusyWindow] {
            let candidates = try events(matching: query).filter {
                $0.status != .canceled && $0.availability != .free && $0.endAt > $0.startAt
            }
            guard let first = candidates.first else { return [] }
            var windows: [CalendarBusyWindow] = []
            var current = CalendarBusyWindow(
                startAt: max(first.startAt, query.startAt),
                endAt: min(first.endAt, query.endAt),
                eventIDs: [first.id]
            )
            for event in candidates.dropFirst() {
                let start = max(event.startAt, query.startAt)
                let end = min(event.endAt, query.endAt)
                guard end > start else { continue }
                if start <= current.endAt {
                    current.endAt = max(current.endAt, end)
                    current.eventIDs.append(event.id)
                } else {
                    windows.append(current)
                    current = CalendarBusyWindow(startAt: start, endAt: end, eventIDs: [event.id])
                }
            }
            windows.append(current)
            return windows
        }

        private func requireAccess() throws {
            let status = authorizationStatus()
            guard status == .fullAccess else { throw CalendarClientError.accessNotGranted(status) }
        }

        private func validate(_ query: CalendarEventQuery) throws {
            guard query.endAt > query.startAt else { throw CalendarClientError.invalidRange }
            guard query.endAt.timeIntervalSince(query.startAt) <= CalendarEventQuery.maximumDuration else {
                throw CalendarClientError.rangeTooLarge
            }
        }

        private func resolveCalendar(_ id: String) throws -> EKCalendar {
            guard let calendar = store.calendar(withIdentifier: id) else {
                throw CalendarClientError.calendarNotFound(id)
            }
            return calendar
        }

        private func resolveWritableCalendar(_ id: String) throws -> EKCalendar {
            let calendar = try resolveCalendar(id)
            guard calendar.allowsContentModifications else {
                throw CalendarClientError.calendarNotWritable(id)
            }
            return calendar
        }

        private func normalizedRange(
            start: Date,
            end: Date,
            isAllDay: Bool,
            timeZone: TimeZone
        ) throws -> (start: Date, end: Date) {
            if isAllDay {
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = timeZone
                let start = calendar.startOfDay(for: start)
                let end = calendar.startOfDay(for: end)
                guard end > start else {
                    throw CalendarClientError.invalidInput("All-day end_at is exclusive and must be after start_at.")
                }
                return (start, end)
            }
            guard end >= start else { throw CalendarClientError.invalidRange }
            return (start, end)
        }

        private func resolveTimeZone(_ identifier: String?) throws -> TimeZone? {
            guard let identifier else { return nil }
            guard let result = TimeZone(identifier: identifier) else {
                throw CalendarClientError.invalidInput("time_zone must be an IANA time zone identifier.")
            }
            return result
        }

        private func makeAlarm(_ input: CalendarAlarmInput) throws -> EKAlarm {
            let alarm: EKAlarm
            let email: String?
            switch input {
            case .relative(let minutes, let address):
                guard (0...CalendarAlarmInput.maximumRelativeMinutes).contains(minutes) else {
                    throw CalendarClientError.invalidInput("Alarm minutes are out of range.")
                }
                alarm = EKAlarm(relativeOffset: -Double(minutes) * 60)
                email = address
            case .absolute(let at, let address):
                alarm = EKAlarm(absoluteDate: at)
                email = address
            case .proximity(let proximity, let title, let latitude, let longitude, let radius, let address):
                guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    (-90...90).contains(latitude), (-180...180).contains(longitude), radius > 0
                else { throw CalendarClientError.invalidInput("Invalid proximity alarm location.") }
                alarm = EKAlarm()
                alarm.proximity = proximity == .enter ? .enter : .leave
                let location = EKStructuredLocation(title: title)
                location.geoLocation = CLLocation(latitude: latitude, longitude: longitude)
                location.radius = radius
                alarm.structuredLocation = location
                email = address
            }
            if let email = email?.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty {
                alarm.emailAddress = email
            }
            return alarm
        }

        private func makeRecurrence(_ rule: CalendarRecurrenceRule) throws -> EKRecurrenceRule {
            try validateRecurrence(rule)
            let end: EKRecurrenceEnd?
            switch rule.end {
            case .occurrenceCount(let count): end = EKRecurrenceEnd(occurrenceCount: count)
            case .endDate(let date): end = EKRecurrenceEnd(end: date)
            case nil: end = nil
            }
            return EKRecurrenceRule(
                recurrenceWith: rule.frequency.eventKitValue, interval: rule.interval,
                daysOfTheWeek: rule.daysOfTheWeek.map {
                    EKRecurrenceDayOfWeek($0.day.eventKitValue, weekNumber: $0.weekNumber)
                }.nilIfEmpty,
                daysOfTheMonth: rule.daysOfTheMonth.map(NSNumber.init(value:)).nilIfEmpty,
                monthsOfTheYear: rule.monthsOfTheYear.map(NSNumber.init(value:)).nilIfEmpty,
                weeksOfTheYear: rule.weeksOfTheYear.map(NSNumber.init(value:)).nilIfEmpty,
                daysOfTheYear: rule.daysOfTheYear.map(NSNumber.init(value:)).nilIfEmpty,
                setPositions: rule.setPositions.map(NSNumber.init(value:)).nilIfEmpty, end: end)
        }

        private func validateRecurrences(_ rules: [CalendarRecurrenceRule], start: Date) throws {
            for rule in rules {
                try validateRecurrence(rule)
                if case .endDate(let end)? = rule.end, end < start {
                    throw CalendarClientError.invalidInput("recurrence.end_at must not precede event start.")
                }
            }
        }

        private func validateRecurrence(_ rule: CalendarRecurrenceRule) throws {
            guard (1...CalendarRecurrenceRule.maximumInterval).contains(rule.interval) else {
                throw CalendarClientError.invalidInput("recurrence.interval is out of range.")
            }
            func valid(_ values: [Int], maximum: Int, positive: Bool = false) -> Bool {
                Set(values).count == values.count
                    && values.allSatisfy { (positive ? $0 > 0 : $0 != 0) && abs($0) <= maximum }
            }
            guard valid(rule.daysOfTheMonth, maximum: 31), valid(rule.monthsOfTheYear, maximum: 12, positive: true),
                valid(rule.weeksOfTheYear, maximum: 53), valid(rule.daysOfTheYear, maximum: 366),
                valid(rule.setPositions, maximum: 366), Set(rule.daysOfTheWeek).count == rule.daysOfTheWeek.count
            else { throw CalendarClientError.invalidInput("recurrence contains invalid or duplicate selectors.") }
            if case .occurrenceCount(let count)? = rule.end, count < 1 {
                throw CalendarClientError.invalidInput("recurrence.occurrence_count must be positive.")
            }
            switch rule.frequency {
            case .daily:
                guard rule.daysOfTheWeek.isEmpty, rule.daysOfTheMonth.isEmpty,
                    rule.monthsOfTheYear.isEmpty, rule.weeksOfTheYear.isEmpty,
                    rule.daysOfTheYear.isEmpty, rule.setPositions.isEmpty
                else { throw CalendarClientError.invalidInput("daily recurrence does not accept BY selectors.") }
            case .weekly:
                guard rule.daysOfTheMonth.isEmpty, rule.monthsOfTheYear.isEmpty,
                    rule.weeksOfTheYear.isEmpty, rule.daysOfTheYear.isEmpty,
                    rule.daysOfTheWeek.allSatisfy({ $0.weekNumber == 0 })
                else { throw CalendarClientError.invalidInput("weekly recurrence has invalid selectors.") }
            case .monthly:
                guard rule.monthsOfTheYear.isEmpty, rule.weeksOfTheYear.isEmpty,
                    rule.daysOfTheYear.isEmpty,
                    rule.daysOfTheWeek.allSatisfy({ abs($0.weekNumber) <= 5 })
                else { throw CalendarClientError.invalidInput("monthly recurrence has invalid selectors.") }
            case .yearly:
                guard rule.daysOfTheMonth.isEmpty,
                    rule.daysOfTheWeek.allSatisfy({ abs($0.weekNumber) <= 53 })
                else { throw CalendarClientError.invalidInput("yearly recurrence has invalid selectors.") }
            }
            if !rule.setPositions.isEmpty, rule.daysOfTheWeek.isEmpty,
                rule.daysOfTheMonth.isEmpty, rule.monthsOfTheYear.isEmpty,
                rule.weeksOfTheYear.isEmpty, rule.daysOfTheYear.isEmpty
            {
                throw CalendarClientError.invalidInput("recurrence.by_set_pos requires another selector.")
            }
        }

        private func apply<Value>(_ update: CalendarFieldUpdate<Value>, to value: inout Value?) {
            switch update {
            case .unchanged:
                break
            case .set(let newValue):
                value = newValue
            case .clear:
                value = nil
            }
        }

        private func resolveEvent(_ identity: CalendarEventIdentity) throws -> EKEvent {
            if let direct = store.event(withIdentifier: identity.eventID), Self.matches(direct, identity) {
                return direct
            }
            if let occurrence = identity.occurrence {
                let predicate = store.predicateForEvents(
                    withStart: occurrence.occurrenceStart.addingTimeInterval(-1),
                    end: occurrence.occurrenceStart.addingTimeInterval(24 * 60 * 60),
                    calendars: nil
                )
                if let match = store.events(matching: predicate).first(where: { Self.matches($0, identity) }) {
                    return match
                }
            }
            throw CalendarClientError.eventNotFound(identity)
        }

        private static func matches(_ event: EKEvent, _ identity: CalendarEventIdentity) -> Bool {
            guard event.eventIdentifier == identity.eventID || event.calendarItemIdentifier == identity.eventID else {
                return false
            }
            guard event.calendar?.calendarIdentifier == identity.calendarID,
                event.calendar?.source.sourceIdentifier == identity.sourceID
            else { return false }
            guard let occurrence = identity.occurrence else { return true }
            let actualMatches = abs(event.startDate.timeIntervalSince(occurrence.occurrenceStart)) < 1
            let originalMatches =
                event.occurrenceDate.map {
                    abs($0.timeIntervalSince(occurrence.originalStart)) < 1
                } ?? false
            return actualMatches && originalMatches
        }

        private static func mapCalendar(_ calendar: EKCalendar) -> CalendarRecord {
            CalendarRecord(
                id: calendar.calendarIdentifier,
                title: calendar.title,
                source: CalendarSourceRecord(
                    id: calendar.source.sourceIdentifier,
                    title: calendar.source.title,
                    type: calendar.source.sourceType.modelValue
                ),
                colorHex: calendar.cgColor.flatMap(colorHex),
                isEditable: calendar.allowsContentModifications,
                isSubscribed: calendar.isSubscribed
            )
        }

        private static func mapEvent(_ event: EKEvent) -> CalendarEvent {
            let calendar = event.calendar
            let occurrenceDate = event.hasRecurrenceRules || event.isDetached ? event.occurrenceDate : nil
            let occurrence = occurrenceDate.map {
                CalendarOccurrenceIdentity(
                    occurrenceStart: event.startDate,
                    originalStart: $0,
                    isDetached: event.isDetached
                )
            }
            return CalendarEvent(
                identity: CalendarEventIdentity(
                    eventID: event.eventIdentifier ?? event.calendarItemIdentifier,
                    calendarID: calendar?.calendarIdentifier ?? "",
                    sourceID: calendar?.source.sourceIdentifier ?? "",
                    occurrence: occurrence
                ),
                title: event.title,
                startAt: event.startDate,
                endAt: event.endDate,
                isAllDay: event.isAllDay,
                status: event.status.modelValue,
                availability: event.availability.modelValue,
                location: event.location,
                url: event.url,
                notes: event.notes,
                structuredLocation: event.structuredLocation.map {
                    CalendarStructuredLocation(
                        title: $0.title ?? "", latitude: $0.geoLocation?.coordinate.latitude,
                        longitude: $0.geoLocation?.coordinate.longitude, radius: $0.radius)
                },
                externalID: event.calendarItemExternalIdentifier,
                calendarTitle: calendar?.title ?? "",
                timeZoneIdentifier: event.timeZone?.identifier,
                createdAt: event.creationDate,
                modifiedAt: event.lastModifiedDate,
                alarms: (event.alarms ?? []).map(mapAlarm),
                recurrenceRules: (event.recurrenceRules ?? []).map(mapRecurrence),
                organizer: event.organizer.map(mapParticipant),
                attendees: (event.attendees ?? []).map(mapParticipant)
            )
        }

        private static func mapAlarm(_ alarm: EKAlarm) -> CalendarAlarm {
            let proximity: CalendarAlarmProximity? =
                alarm.proximity == .enter ? .enter : alarm.proximity == .leave ? .leave : nil
            let kind: CalendarAlarmKind =
                proximity != nil ? .proximity : alarm.absoluteDate != nil ? .absolute : .relative
            return CalendarAlarm(
                kind: kind, relativeOffsetMinutes: kind == .relative ? alarm.relativeOffset / 60 : nil,
                absoluteAt: alarm.absoluteDate, proximity: proximity, locationTitle: alarm.structuredLocation?.title,
                latitude: alarm.structuredLocation?.geoLocation?.coordinate.latitude,
                longitude: alarm.structuredLocation?.geoLocation?.coordinate.longitude,
                radius: alarm.structuredLocation?.radius, action: alarm.type.modelValue,
                emailAddress: alarm.emailAddress, soundName: alarm.soundName)
        }

        private static func mapRecurrence(_ rule: EKRecurrenceRule) -> CalendarRecurrenceRule {
            let end: CalendarRecurrenceEnd?
            if let recurrenceEnd = rule.recurrenceEnd, let date = recurrenceEnd.endDate {
                end = .endDate(date)
            } else if let count = rule.recurrenceEnd?.occurrenceCount, count > 0 {
                end = .occurrenceCount(Int(count))
            } else {
                end = nil
            }
            return CalendarRecurrenceRule(
                frequency: rule.frequency.modelValue, interval: rule.interval,
                daysOfTheWeek: (rule.daysOfTheWeek ?? []).map {
                    .init(day: $0.dayOfTheWeek.modelValue, weekNumber: $0.weekNumber)
                },
                daysOfTheMonth: (rule.daysOfTheMonth ?? []).map(\.intValue),
                monthsOfTheYear: (rule.monthsOfTheYear ?? []).map(\.intValue),
                weeksOfTheYear: (rule.weeksOfTheYear ?? []).map(\.intValue),
                daysOfTheYear: (rule.daysOfTheYear ?? []).map(\.intValue),
                setPositions: (rule.setPositions ?? []).map(\.intValue),
                firstDayOfTheWeek: rule.firstDayOfTheWeek == 0
                    ? nil : EKWeekday(rawValue: rule.firstDayOfTheWeek)?.modelValue,
                end: end)
        }

        private static func mapParticipant(_ participant: EKParticipant) -> CalendarParticipant {
            let url = participant.url
            let email =
                url.scheme?.lowercased() == "mailto"
                ? String(url.absoluteString.dropFirst("mailto:".count)).removingPercentEncoding
                : nil
            return CalendarParticipant(
                name: participant.name,
                email: email,
                url: url,
                status: participant.participantStatus.modelValue,
                role: participant.participantRole.modelValue,
                type: participant.participantType.modelValue,
                isCurrentUser: participant.isCurrentUser
            )
        }

        private static func colorHex(_ color: CGColor) -> String? {
            guard
                let converted = color.converted(
                    to: CGColorSpace(name: CGColorSpace.sRGB)!,
                    intent: .defaultIntent,
                    options: nil
                ), let components = converted.components, components.count >= 3
            else { return nil }
            return String(
                format: "#%02X%02X%02X",
                Int(components[0] * 255), Int(components[1] * 255), Int(components[2] * 255)
            )
        }
    }

    private extension EKSourceType {
        var modelValue: CalendarSourceType {
            switch self {
            case .local: .local
            case .exchange: .exchange
            case .calDAV: .calDAV
            case .mobileMe: .mobileMe
            case .subscribed: .subscribed
            case .birthdays: .birthdays
            @unknown default: .unknown
            }
        }
    }

    private extension EKEventStatus {
        var modelValue: CalendarEventStatus {
            switch self {
            case .none: .none
            case .tentative: .tentative
            case .confirmed: .confirmed
            case .canceled: .canceled
            @unknown default: .none
            }
        }
    }

    private extension EKEventAvailability {
        var modelValue: CalendarEventAvailability {
            switch self {
            case .notSupported: .unknown
            case .busy: .busy
            case .free: .free
            case .tentative: .tentative
            case .unavailable: .unavailable
            @unknown default: .unknown
            }
        }
    }

    private extension CalendarEventAvailability {
        var eventKitValue: EKEventAvailability {
            switch self {
            case .unknown: .notSupported
            case .busy: .busy
            case .free: .free
            case .tentative: .tentative
            case .unavailable: .unavailable
            }
        }
    }

    private extension EKParticipantStatus {
        var modelValue: CalendarParticipantStatus {
            switch self {
            case .unknown: .unknown
            case .pending: .pending
            case .accepted: .accepted
            case .declined: .declined
            case .tentative: .tentative
            case .delegated: .delegated
            case .completed: .completed
            case .inProcess: .inProcess
            @unknown default: .unknown
            }
        }
    }

    private extension EKParticipantRole {
        var modelValue: CalendarParticipantRole {
            switch self {
            case .unknown: .unknown
            case .required: .required
            case .optional: .optional
            case .chair: .chair
            case .nonParticipant: .nonParticipant
            @unknown default: .unknown
            }
        }
    }

    private extension EKParticipantType {
        var modelValue: CalendarParticipantType {
            switch self {
            case .unknown: .unknown
            case .person: .person
            case .room: .room
            case .resource: .resource
            case .group: .group
            @unknown default: .unknown
            }
        }
    }

    private extension CalendarEventMutationSpan {
        var eventKitValue: EKSpan {
            switch self {
            case .thisEvent: .thisEvent
            case .futureEvents: .futureEvents
            }
        }
    }

    private extension Array {
        var nilIfEmpty: Self? { isEmpty ? nil : self }
    }

    private extension CalendarRecurrenceFrequency {
        var eventKitValue: EKRecurrenceFrequency {
            switch self {
            case .daily: .daily;
            case .weekly: .weekly;
            case .monthly: .monthly;
            case .yearly: .yearly
            }
        }
    }

    private extension EKRecurrenceFrequency {
        var modelValue: CalendarRecurrenceFrequency {
            switch self {
            case .daily: .daily;
            case .weekly: .weekly;
            case .monthly: .monthly;
            case .yearly: .yearly;
            @unknown default: .daily
            }
        }
    }

    private extension CalendarWeekday {
        var eventKitValue: EKWeekday {
            switch self {
            case .sunday: .sunday;
            case .monday: .monday;
            case .tuesday: .tuesday;
            case .wednesday: .wednesday;
            case .thursday: .thursday;
            case .friday: .friday;
            case .saturday: .saturday
            }
        }
    }

    private extension EKWeekday {
        var modelValue: CalendarWeekday {
            switch self {
            case .sunday: .sunday;
            case .monday: .monday;
            case .tuesday: .tuesday;
            case .wednesday: .wednesday;
            case .thursday: .thursday;
            case .friday: .friday;
            case .saturday: .saturday;
            @unknown default: .sunday
            }
        }
    }

    private extension EKAlarmType {
        var modelValue: CalendarAlarmAction {
            switch self {
            case .display: .display;
            case .audio: .audio;
            case .procedure: .procedure;
            case .email: .email;
            @unknown default: .unknown
            }
        }
    }
#endif
