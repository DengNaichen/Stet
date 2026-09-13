import Foundation
import MCP

struct MCPCalendarTools: Sendable {
    nonisolated static let listCalendarsToolName = "calendar_calendars_list"
    nonisolated static let fetchEventsToolName = "calendar_events_fetch"
    nonisolated static let getEventToolName = "calendar_events_get"
    nonisolated static let freeBusyToolName = "calendar_free_busy"
    nonisolated static let createEventToolName = "calendar_events_create"
    nonisolated static let updateEventToolName = "calendar_events_update"
    nonisolated static let deleteEventToolName = "calendar_events_delete"
    nonisolated static let readNames: Set<String> = [
        listCalendarsToolName, fetchEventsToolName, getEventToolName, freeBusyToolName,
    ]
    nonisolated static let writeNames: Set<String> = [createEventToolName, updateEventToolName, deleteEventToolName]

    let readClient: any CalendarReadClient
    let writeClient: (any CalendarWriteClient)?

    nonisolated init(
        readClient: any CalendarReadClient,
        writeClient: (any CalendarWriteClient)? = nil
    ) {
        self.readClient = readClient
        self.writeClient = writeClient
    }

    var tools: [Tool] {
        Self.readTools + (writeClient == nil ? [] : Self.writeTools)
    }

    @MainActor
    func call(_ parameters: CallTool.Parameters) async -> CallTool.Result {
        do {
            switch parameters.name {
            case Self.listCalendarsToolName: return try listCalendars()
            case Self.fetchEventsToolName: return try fetchEvents(parameters.arguments)
            case Self.getEventToolName: return try getEvent(parameters.arguments)
            case Self.freeBusyToolName: return try freeBusy(parameters.arguments)
            case Self.createEventToolName: return try createEvent(parameters.arguments)
            case Self.updateEventToolName: return try updateEvent(parameters.arguments)
            case Self.deleteEventToolName: return try deleteEvent(parameters.arguments)
            default: return MCPToolSupport.error("Unknown tool: \(parameters.name)")
            }
        } catch {
            return MCPToolSupport.error(error.localizedDescription)
        }
    }

    private func listCalendars() throws -> CallTool.Result {
        let output = CalendarListOutput(calendars: try readClient.calendars().map(CalendarOutput.init))
        return try MCPToolSupport.result(text: "Found \(output.calendars.count) calendars.", output: output)
    }

    private func fetchEvents(_ arguments: [String: Value]?) throws -> CallTool.Result {
        let values = arguments ?? [:]
        let query = try eventQuery(values)
        let includeAllDay = try MCPToolSupport.bool("include_all_day", in: values, default: true)
        let status = try enumValue(CalendarEventStatus.self, key: "status", in: values)
        let availability = try enumValue(CalendarEventAvailability.self, key: "availability", in: values)
        let hasAlarms = try optionalBool("has_alarms", in: values)
        let recurring = try optionalBool("is_recurring", in: values)
        let search = values["query"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        let events = try readClient.events(matching: query).filter { event in
            (includeAllDay || !event.isAllDay)
                && (status == nil || event.status == status)
                && (availability == nil || event.availability == availability)
                && (hasAlarms == nil || event.hasAlarms == hasAlarms)
                && (recurring == nil || event.isRecurring == recurring)
                && (search?.isEmpty != false || matches(event, search: search!))
        }
        let output = EventListOutput(events: events.map(EventOutput.init))
        return try MCPToolSupport.result(text: "Found \(events.count) calendar events.", output: output)
    }

    private func getEvent(_ arguments: [String: Value]?) throws -> CallTool.Result {
        let event = try readClient.event(identity(arguments ?? [:]))
        return try MCPToolSupport.result(text: event.title ?? "Untitled event", output: EventOutput(event))
    }

    private func freeBusy(_ arguments: [String: Value]?) throws -> CallTool.Result {
        let values = arguments ?? [:]
        let includeAllDay = try MCPToolSupport.bool("include_all_day", in: values, default: true)
        let includeTentative = try MCPToolSupport.bool("include_tentative", in: values, default: true)
        let query = try eventQuery(values)
        guard query.endAt.timeIntervalSince(query.startAt) <= 31 * 86_400 else {
            throw MCPToolInputError.invalid("Free/busy ranges cannot exceed 31 days.")
        }
        let candidates = try readClient.events(matching: query).filter {
            $0.status != .canceled && $0.availability != .free && $0.endAt > $0.startAt
                && (includeAllDay || !$0.isAllDay)
                && (includeTentative || ($0.status != .tentative && $0.availability != .tentative))
        }
        guard candidates.count <= 250 else {
            throw MCPToolInputError.invalid("Free/busy matched too many events; narrow the range or calendars.")
        }
        let windows = mergeBusy(candidates, query: query)
        let eventByID = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0) })
        let busy = windows.map { BusyWindowOutput($0, events: eventByID) }
        let free = freeWindows(query: query, busy: windows)
        let conflicts = conflictWindows(events: candidates, query: query)
        let output = FreeBusyOutput(
            from: MCPToolSupport.iso8601(query.startAt), to: MCPToolSupport.iso8601(query.endAt),
            busy: busy, free: free, conflicts: conflicts)
        return try MCPToolSupport.result(text: "Found \(windows.count) busy windows.", output: output)
    }

    private func createEvent(_ arguments: [String: Value]?) throws -> CallTool.Result {
        let client = try requiredWriteClient()
        let values = arguments ?? [:]
        let timeZoneIdentifier = try timeZone("time_zone", in: values)
        let eventTimeZone = timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? .current
        let startAt = try requiredDate("start_at", in: values, timeZone: eventTimeZone)
        let endAt = try requiredDate("end_at", in: values, timeZone: eventTimeZone)
        let calendarID = try resolveWriteCalendar(values)
        let isAllDay = try MCPToolSupport.bool("is_all_day", in: values, default: false)
        try validateRange(start: startAt, end: endAt, isAllDay: isAllDay)
        let recurrence = try recurrence("recurrence", in: values)
        let availability = try enumValue(CalendarEventAvailability.self, key: "availability", in: values) ?? .busy
        guard availability != .unknown else {
            throw MCPToolInputError.invalid("availability must be busy, free, tentative, or unavailable.")
        }
        let event = try client.create(
            CalendarEventCreateRequest(
                calendarID: calendarID,
                title: try MCPToolSupport.requiredString("title", in: values),
                startAt: startAt,
                endAt: endAt,
                isAllDay: isAllDay,
                availability: availability,
                location: values["location"]?.stringValue,
                url: try optionalURL("url", in: values),
                notes: values["notes"]?.stringValue,
                timeZoneIdentifier: timeZoneIdentifier,
                alarms: try alarms("alarms", in: values) ?? [],
                recurrenceRules: recurrence.map { [$0] } ?? []
            ))
        return try MCPToolSupport.result(text: "Created calendar event.", output: EventOutput(event))
    }

    private func updateEvent(_ arguments: [String: Value]?) throws -> CallTool.Result {
        let client = try requiredWriteClient()
        let values = arguments ?? [:]
        let identity = try identity(values)
        let existing = try client.event(identity)
        try validateRecurringMutation(existing: existing, identity: identity, span: try span(values))
        let metadata = Set(["id", "occurrence_start", "original_start_at", "span"])
        guard values.keys.contains(where: { !metadata.contains($0) }) else {
            throw MCPToolInputError.invalid("At least one event field must be updated.")
        }
        let calendarID = try resolveOptionalWriteCalendar(values)
        let recurrenceUpdate = try recurrenceUpdate("recurrence", in: values)
        let availability = try enumValue(CalendarEventAvailability.self, key: "availability", in: values)
        guard availability != .unknown else {
            throw MCPToolInputError.invalid("availability must be busy, free, tentative, or unavailable.")
        }
        let timeZoneUpdate = try timeZoneUpdate("time_zone", in: values)
        let eventTimeZone = try resolvedTimeZone(update: timeZoneUpdate, existing: existing.timeZoneIdentifier)
        let request = CalendarEventUpdateRequest(
            title: values["title"]?.stringValue,
            startAt: try MCPToolSupport.date("start_at", in: values, required: false, timeZone: eventTimeZone),
            endAt: try MCPToolSupport.date("end_at", in: values, required: false, timeZone: eventTimeZone),
            calendarID: calendarID,
            isAllDay: try optionalBool("is_all_day", in: values),
            availability: availability,
            location: try stringUpdate("location", in: values),
            url: try urlUpdate("url", in: values),
            notes: try stringUpdate("notes", in: values),
            timeZoneIdentifier: timeZoneUpdate,
            alarms: try alarmsUpdate("alarms", in: values),
            recurrenceRules: recurrenceUpdate
        )
        try validateRange(
            start: request.startAt ?? existing.startAt, end: request.endAt ?? existing.endAt,
            isAllDay: request.isAllDay ?? existing.isAllDay)
        let event = try client.update(identity, with: request, span: try span(values))
        return try MCPToolSupport.result(text: "Updated calendar event.", output: EventOutput(event))
    }

    private func deleteEvent(_ arguments: [String: Value]?) throws -> CallTool.Result {
        let client = try requiredWriteClient()
        let values = arguments ?? [:]
        guard try MCPToolSupport.bool("confirm", in: values, default: false) else {
            throw MCPToolInputError.invalid("confirm must be true to delete an event.")
        }
        let identity = try identity(values)
        let existing = try client.event(identity)
        let mutationSpan = try span(values)
        try validateRecurringMutation(existing: existing, identity: identity, span: mutationSpan)
        try client.delete(identity, span: mutationSpan)
        return try MCPToolSupport.result(
            text: "Deleted calendar event.",
            output: DeleteOutput(
                deleted: true, id: calendarOpaqueID(existing),
                occurrenceStart: identity.occurrence.map { MCPToolSupport.iso8601($0.occurrenceStart) },
                originalStartAt: identity.occurrence.map { MCPToolSupport.iso8601($0.originalStart) },
                span: mutationSpan == .thisEvent ? "this_event" : "future_events",
                title: existing.title ?? "", calendarID: existing.identity.calendarID,
                calendarTitle: existing.calendarTitle))
    }

    private func requiredWriteClient() throws -> any CalendarWriteClient {
        guard let writeClient else { throw MCPToolInputError.invalid("Calendar modifications are unavailable.") }
        return writeClient
    }

    private func eventQuery(_ values: [String: Value]) throws -> CalendarEventQuery {
        let parsedFrom = try dateInput("from", in: values)
        let parsedTo = try dateInput("to", in: values)
        var from = parsedFrom?.date ?? Date()
        var to = parsedTo?.date ?? Calendar.current.date(byAdding: .day, value: 7, to: from)!
        if parsedFrom == nil, parsedTo?.dateOnly == true { from = parsedTo!.date }
        if parsedTo?.dateOnly == true { to = Calendar.current.date(byAdding: .day, value: 1, to: to)! }
        if parsedTo == nil, parsedFrom?.dateOnly == true {
            to = Calendar.current.date(byAdding: .day, value: 1, to: from)!
        }
        let calendarIDs = try resolveReadCalendars(values)
        return CalendarEventQuery(startAt: from, endAt: to, calendarIDs: Set(calendarIDs))
    }

    private func identity(_ values: [String: Value]) throws -> CalendarEventIdentity {
        let encoded = try MCPToolSupport.requiredString("id", in: values)
        guard let data = Data(base64Encoded: encoded),
            let base = try? JSONDecoder().decode(EventIdentityWire.self, from: data)
        else {
            throw MCPToolInputError.invalid("id is not a valid calendar event ID.")
        }
        let occurrenceStart = try MCPToolSupport.date("occurrence_start", in: values, required: false)
        let originalStart = try MCPToolSupport.date("original_start_at", in: values, required: false)
        guard (occurrenceStart == nil) == (originalStart == nil) else {
            throw MCPToolInputError.invalid("occurrence_start and original_start_at must be provided together.")
        }
        let occurrence = occurrenceStart.map {
            CalendarOccurrenceIdentity(occurrenceStart: $0, originalStart: originalStart!, isDetached: base.isDetached)
        }
        return CalendarEventIdentity(
            eventID: base.eventID,
            calendarID: base.calendarID,
            sourceID: base.sourceID,
            occurrence: occurrence
        )
    }

    private nonisolated func span(_ values: [String: Value]) throws -> CalendarEventMutationSpan {
        switch values["span"]?.stringValue ?? "this_event" {
        case "this_event": return .thisEvent
        case "future_events": return .futureEvents
        default: throw MCPToolInputError.invalid("span must be this_event or future_events.")
        }
    }

    private nonisolated func requiredDate(
        _ key: String,
        in values: [String: Value],
        timeZone: TimeZone = .current
    ) throws -> Date {
        guard let date = try MCPToolSupport.date(key, in: values, timeZone: timeZone) else {
            throw MCPToolInputError.invalid("\(key) is required.")
        }
        return date
    }

    private nonisolated func resolvedTimeZone(
        update: CalendarFieldUpdate<String>,
        existing: String?
    ) throws -> TimeZone {
        let identifier: String?
        switch update {
        case .unchanged:
            identifier = existing
        case .set(let value):
            identifier = value
        case .clear:
            identifier = nil
        }
        guard let identifier else { return .current }
        guard let timeZone = TimeZone(identifier: identifier) else {
            throw MCPToolInputError.invalid("time_zone must be an IANA time zone identifier.")
        }
        return timeZone
    }

    private nonisolated func stringArray(_ key: String, in values: [String: Value]) throws -> [String] {
        guard let value = values[key] else { return [] }
        guard let array = value.arrayValue else { throw MCPToolInputError.invalid("\(key) must be an array.") }
        return try array.map { value in
            guard let string = value.stringValue else {
                throw MCPToolInputError.invalid("\(key) must contain strings.")
            }
            return string
        }
    }

    private nonisolated func optionalBool(_ key: String, in values: [String: Value]) throws -> Bool? {
        guard let value = values[key] else { return nil }
        guard let parsed = value.boolValue else { throw MCPToolInputError.invalid("\(key) must be a boolean.") }
        return parsed
    }

    private nonisolated func enumValue<T: RawRepresentable>(_ type: T.Type, key: String, in values: [String: Value])
        throws -> T?
    where T.RawValue == String {
        guard let rawValue = values[key] else { return nil }
        guard let raw = rawValue.stringValue else {
            throw MCPToolInputError.invalid("\(key) must be a string.")
        }
        guard let value = T(rawValue: raw) else { throw MCPToolInputError.invalid("Invalid \(key) value.") }
        return value
    }

    private nonisolated func optionalURL(_ key: String, in values: [String: Value]) throws -> URL? {
        guard let value = values[key] else { return nil }
        if value.isNull { return nil }
        guard let raw = value.stringValue else {
            throw MCPToolInputError.invalid("\(key) must be a URL string or null.")
        }
        guard let url = URL(string: raw), url.scheme != nil else {
            throw MCPToolInputError.invalid("\(key) must be a valid URL.")
        }
        return url
    }

    private nonisolated func stringUpdate(
        _ key: String,
        in values: [String: Value]
    ) throws -> CalendarFieldUpdate<String> {
        guard let value = values[key] else { return .unchanged }
        if value.isNull { return .clear }
        guard let string = value.stringValue else {
            throw MCPToolInputError.invalid("\(key) must be a string or null.")
        }
        return .set(string)
    }

    private nonisolated func urlUpdate(_ key: String, in values: [String: Value]) throws -> CalendarFieldUpdate<URL> {
        guard let value = values[key] else { return .unchanged }
        if value.isNull { return .clear }
        guard let url = try optionalURL(key, in: values) else {
            throw MCPToolInputError.invalid("\(key) must be a URL string or null.")
        }
        return .set(url)
    }

    private func resolveReadCalendars(_ values: [String: Value]) throws -> [String] {
        let ids = try stringArray("calendar_ids", in: values)
        let names = try stringArray("list_names", in: values)
        let calendars = try readClient.calendars()
        var result = ids
        for name in names {
            let matches = calendars.filter { $0.title.caseInsensitiveCompare(name) == .orderedSame }
            guard !matches.isEmpty else { throw CalendarClientError.calendarNotFound(name) }
            guard matches.count == 1 else {
                throw CalendarClientError.ambiguousCalendarTitle(name, matches.map(\.id).sorted())
            }
            result.append(matches[0].id)
        }
        if result.isEmpty { result = calendars.map(\.id) }
        return Array(Set(result)).sorted()
    }

    private func resolveWriteCalendar(_ values: [String: Value]) throws -> String {
        if let id = try resolveOptionalWriteCalendar(values) { return id }
        if let id = try readClient.defaultCalendarID(),
            try readClient.calendars().contains(where: { $0.id == id && $0.isEditable })
        {
            return id
        }
        throw CalendarClientError.defaultCalendarUnavailable
    }

    private func resolveOptionalWriteCalendar(_ values: [String: Value]) throws -> String? {
        let id = values["calendar_id"]?.stringValue
        let name = values["list_name"]?.stringValue
        guard id == nil || name == nil else {
            throw MCPToolInputError.invalid("Provide calendar_id or list_name, not both.")
        }
        if let id { return id }
        guard let name else { return nil }
        let matches = try readClient.calendars().filter { $0.title.caseInsensitiveCompare(name) == .orderedSame }
        guard !matches.isEmpty else { throw CalendarClientError.calendarNotFound(name) }
        guard matches.count == 1 else {
            throw CalendarClientError.ambiguousCalendarTitle(name, matches.map(\.id).sorted())
        }
        return matches[0].id
    }

    private nonisolated func dateInput(_ key: String, in values: [String: Value]) throws -> (
        date: Date, dateOnly: Bool
    )? {
        guard let raw = values[key]?.stringValue else { return nil }
        guard let date = try MCPToolSupport.date(key, in: values) else { return nil }
        return (date, raw.count == 10)
    }

    private nonisolated func validateRange(start: Date, end: Date, isAllDay: Bool) throws {
        guard isAllDay ? Calendar.current.startOfDay(for: end) > Calendar.current.startOfDay(for: start) : end >= start
        else {
            throw MCPToolInputError.invalid(
                isAllDay
                    ? "All-day end_at is exclusive and must be a calendar day after start_at."
                    : "end_at must not be earlier than start_at.")
        }
    }

    private nonisolated func timeZone(_ key: String, in values: [String: Value]) throws -> String? {
        guard let value = values[key] else { return nil }
        if value.isNull { return nil }
        guard let identifier = value.stringValue else {
            throw MCPToolInputError.invalid("\(key) must be an IANA time zone identifier or null.")
        }
        guard TimeZone(identifier: identifier) != nil else {
            throw MCPToolInputError.invalid("\(key) must be an IANA time zone identifier.")
        }
        return identifier
    }

    private nonisolated func timeZoneUpdate(_ key: String, in values: [String: Value]) throws -> CalendarFieldUpdate<
        String
    > {
        guard let value = values[key] else { return .unchanged }
        if value.isNull { return .clear }
        guard let identifier = try timeZone(key, in: values) else {
            throw MCPToolInputError.invalid("\(key) must be an IANA time zone identifier or null.")
        }
        return .set(identifier)
    }

    private nonisolated func alarms(_ key: String, in values: [String: Value]) throws -> [CalendarAlarmInput]? {
        guard let value = values[key] else { return nil }
        guard let array = value.arrayValue else { throw MCPToolInputError.invalid("\(key) must be an array.") }
        guard array.count <= 20 else { throw MCPToolInputError.invalid("\(key) cannot contain more than 20 alarms.") }
        return try array.enumerated().map { index, value in
            guard let object = value.objectValue else {
                throw MCPToolInputError.invalid("\(key)[\(index)] must be an object.")
            }
            let type = try MCPToolSupport.requiredString("type", in: object)
            let email = object["email_address"]?.stringValue
            switch type {
            case "relative":
                guard let minutes = object["minutes"]?.intValue,
                    (0...CalendarAlarmInput.maximumRelativeMinutes).contains(minutes)
                else { throw MCPToolInputError.invalid("\(key)[\(index)].minutes is invalid.") }
                return .relative(minutes: minutes, emailAddress: email)
            case "absolute":
                return .absolute(at: try requiredDate("at", in: object), emailAddress: email)
            case "proximity":
                guard let latitude = object["latitude"]?.doubleValue, (-90...90).contains(latitude),
                    let longitude = object["longitude"]?.doubleValue, (-180...180).contains(longitude)
                else { throw MCPToolInputError.invalid("\(key)[\(index)] has invalid coordinates.") }
                let radius = object["radius"]?.doubleValue ?? 200
                guard radius > 0 else { throw MCPToolInputError.invalid("\(key)[\(index)].radius must be positive.") }
                let proximity = object["proximity"]?.stringValue ?? "enter"
                guard let proximity = CalendarAlarmProximity(rawValue: proximity) else {
                    throw MCPToolInputError.invalid("\(key)[\(index)].proximity is invalid.")
                }
                return .proximity(
                    proximity: proximity,
                    locationTitle: try MCPToolSupport.requiredString("location_title", in: object),
                    latitude: latitude, longitude: longitude, radius: radius, emailAddress: email)
            default: throw MCPToolInputError.invalid("\(key)[\(index)].type is invalid.")
            }
        }
    }

    private nonisolated func alarmsUpdate(_ key: String, in values: [String: Value]) throws -> [CalendarAlarmInput]? {
        guard let value = values[key] else { return nil }
        if value.isNull { return [] }
        guard value.arrayValue != nil else {
            throw MCPToolInputError.invalid("\(key) must be an array or null.")
        }
        return try alarms(key, in: values)
    }

    private nonisolated func recurrenceUpdate(_ key: String, in values: [String: Value]) throws
        -> [CalendarRecurrenceRule]?
    {
        guard let value = values[key] else { return nil }
        if value.isNull { return [] }
        guard value.objectValue != nil else {
            throw MCPToolInputError.invalid("\(key) must be an object or null.")
        }
        return try recurrence(key, in: values).map { [$0] }
    }

    private nonisolated func recurrence(_ key: String, in values: [String: Value]) throws -> CalendarRecurrenceRule? {
        guard let value = values[key] else { return nil }
        guard let object = value.objectValue else { throw MCPToolInputError.invalid("\(key) must be an object.") }
        guard
            let frequency = CalendarRecurrenceFrequency(
                rawValue: try MCPToolSupport.requiredString("frequency", in: object))
        else {
            throw MCPToolInputError.invalid("\(key).frequency is invalid.")
        }
        let interval = object["interval"]?.intValue ?? 1
        let endDate = try MCPToolSupport.date("end_at", in: object, required: false)
        let count = object["occurrence_count"]?.intValue
        guard endDate == nil || count == nil else {
            throw MCPToolInputError.invalid("recurrence end_at and occurrence_count are mutually exclusive.")
        }
        let end: CalendarRecurrenceEnd? =
            endDate.map(CalendarRecurrenceEnd.endDate) ?? count.map(CalendarRecurrenceEnd.occurrenceCount)
        let rule = CalendarRecurrenceRule(
            frequency: frequency, interval: interval,
            daysOfTheWeek: try weekdays("by_day", in: object),
            daysOfTheMonth: try integers("by_month_day", in: object),
            monthsOfTheYear: try integers("by_month", in: object),
            weeksOfTheYear: try integers("by_week_no", in: object),
            daysOfTheYear: try integers("by_year_day", in: object),
            setPositions: try integers("by_set_pos", in: object), end: end)
        try validateRecurrence(rule)
        return rule
    }

    private nonisolated func validateRecurrence(_ rule: CalendarRecurrenceRule) throws {
        guard (1...CalendarRecurrenceRule.maximumInterval).contains(rule.interval) else {
            throw MCPToolInputError.invalid("recurrence.interval is out of range.")
        }
        func valid(_ values: [Int], maximum: Int, positive: Bool = false) -> Bool {
            Set(values).count == values.count
                && values.allSatisfy { (positive ? $0 > 0 : $0 != 0) && abs($0) <= maximum }
        }
        guard valid(rule.daysOfTheMonth, maximum: 31),
            valid(rule.monthsOfTheYear, maximum: 12, positive: true),
            valid(rule.weeksOfTheYear, maximum: 53),
            valid(rule.daysOfTheYear, maximum: 366),
            valid(rule.setPositions, maximum: 366),
            Set(rule.daysOfTheWeek).count == rule.daysOfTheWeek.count
        else { throw MCPToolInputError.invalid("recurrence contains invalid or duplicate selectors.") }
        if case .occurrenceCount(let count)? = rule.end, count < 1 {
            throw MCPToolInputError.invalid("recurrence.occurrence_count must be positive.")
        }
        switch rule.frequency {
        case .daily:
            guard rule.daysOfTheWeek.isEmpty, rule.daysOfTheMonth.isEmpty,
                rule.monthsOfTheYear.isEmpty, rule.weeksOfTheYear.isEmpty,
                rule.daysOfTheYear.isEmpty, rule.setPositions.isEmpty
            else { throw MCPToolInputError.invalid("daily recurrence does not accept BY selectors.") }
        case .weekly:
            guard rule.daysOfTheMonth.isEmpty, rule.monthsOfTheYear.isEmpty,
                rule.weeksOfTheYear.isEmpty, rule.daysOfTheYear.isEmpty,
                rule.daysOfTheWeek.allSatisfy({ $0.weekNumber == 0 })
            else { throw MCPToolInputError.invalid("weekly recurrence has invalid selectors.") }
        case .monthly:
            guard rule.monthsOfTheYear.isEmpty, rule.weeksOfTheYear.isEmpty,
                rule.daysOfTheYear.isEmpty,
                rule.daysOfTheWeek.allSatisfy({ abs($0.weekNumber) <= 5 })
            else { throw MCPToolInputError.invalid("monthly recurrence has invalid selectors.") }
        case .yearly:
            guard rule.daysOfTheMonth.isEmpty,
                rule.daysOfTheWeek.allSatisfy({ abs($0.weekNumber) <= 53 })
            else { throw MCPToolInputError.invalid("yearly recurrence has invalid selectors.") }
        }
        if !rule.setPositions.isEmpty, rule.daysOfTheWeek.isEmpty,
            rule.daysOfTheMonth.isEmpty, rule.monthsOfTheYear.isEmpty,
            rule.weeksOfTheYear.isEmpty, rule.daysOfTheYear.isEmpty
        {
            throw MCPToolInputError.invalid("recurrence.by_set_pos requires another selector.")
        }
    }

    private nonisolated func integers(_ key: String, in values: [String: Value]) throws -> [Int] {
        guard let value = values[key] else { return [] }
        guard let array = value.arrayValue else { throw MCPToolInputError.invalid("\(key) must be an array.") }
        return try array.map {
            guard let integer = $0.intValue else { throw MCPToolInputError.invalid("\(key) must contain integers.") };
            return integer
        }
    }

    private nonisolated func weekdays(_ key: String, in values: [String: Value]) throws -> [CalendarRecurrenceWeekday] {
        let map: [String: CalendarWeekday] = [
            "SU": .sunday, "MO": .monday, "TU": .tuesday, "WE": .wednesday, "TH": .thursday, "FR": .friday,
            "SA": .saturday,
        ]
        return try stringArray(key, in: values).map { token in
            let upper = token.uppercased()
            guard upper.count >= 2, let day = map[String(upper.suffix(2))] else {
                throw MCPToolInputError.invalid("Invalid RFC 5545 weekday '\(token)'.")
            }
            let prefix = String(upper.dropLast(2))
            guard prefix.isEmpty || (Int(prefix).map { $0 != 0 && abs($0) <= 53 } == true) else {
                throw MCPToolInputError.invalid("Invalid RFC 5545 weekday '\(token)'.")
            }
            return CalendarRecurrenceWeekday(day: day, weekNumber: Int(prefix) ?? 0)
        }
    }

    private nonisolated func validateRecurringMutation(
        existing: CalendarEvent, identity: CalendarEventIdentity, span: CalendarEventMutationSpan
    ) throws {
        if existing.isRecurring, identity.occurrence == nil {
            throw MCPToolInputError.invalid(
                "occurrence_start and original_start_at are required for recurring mutations.")
        }
        if span == .futureEvents, !existing.isRecurring {
            throw MCPToolInputError.invalid("future_events requires a recurring event.")
        }
    }

    private nonisolated func matches(_ event: CalendarEvent, search: String) -> Bool {
        [event.title, event.location, event.notes].compactMap { $0 }.contains {
            $0.localizedCaseInsensitiveContains(search)
        }
    }

    private nonisolated func mergeBusy(_ events: [CalendarEvent], query: CalendarEventQuery) -> [CalendarBusyWindow] {
        let sorted = events.sorted { $0.startAt < $1.startAt }
        var output: [CalendarBusyWindow] = []
        for event in sorted {
            let start = max(event.startAt, query.startAt)
            let end = min(event.endAt, query.endAt)
            guard end > start else { continue }
            if let last = output.last, start <= last.endAt {
                output[output.count - 1].endAt = max(last.endAt, end)
                output[output.count - 1].eventIDs.append(event.id)
            } else {
                output.append(CalendarBusyWindow(startAt: start, endAt: end, eventIDs: [event.id]))
            }
        }
        return output
    }

    private nonisolated func freeWindows(query: CalendarEventQuery, busy: [CalendarBusyWindow]) -> [TimeWindowOutput] {
        var cursor = query.startAt
        var output: [TimeWindowOutput] = []
        for window in busy {
            if window.startAt > cursor { output.append(TimeWindowOutput(start: cursor, end: window.startAt)) }
            cursor = max(cursor, window.endAt)
        }
        if cursor < query.endAt { output.append(TimeWindowOutput(start: cursor, end: query.endAt)) }
        return output
    }

    private nonisolated func conflictWindows(events: [CalendarEvent], query: CalendarEventQuery) -> [BusyWindowOutput] {
        let boundaries = Set(events.flatMap { [max($0.startAt, query.startAt), min($0.endAt, query.endAt)] }).sorted()
        guard boundaries.count > 1 else { return [] }
        var result: [BusyWindowOutput] = []
        for pair in zip(boundaries, boundaries.dropFirst()) where pair.1 > pair.0 {
            let active = events.filter { $0.startAt < pair.1 && $0.endAt > pair.0 }
            if active.count >= 2 { result.append(BusyWindowOutput(start: pair.0, end: pair.1, events: active)) }
        }
        return result
    }

    private struct EventIdentityWire: Codable, Sendable {
        let eventID: String
        let calendarID: String
        let sourceID: String
        let isDetached: Bool
    }

    private struct CalendarListOutput: Codable, Sendable { let calendars: [CalendarOutput] }
    private struct EventListOutput: Codable, Sendable { let events: [EventOutput] }
    private struct FreeBusyOutput: Codable, Sendable {
        let from: String
        let to: String
        let busy: [BusyWindowOutput]
        let free: [TimeWindowOutput]
        let conflicts: [BusyWindowOutput]
    }
    private struct DeleteOutput: Codable, Sendable {
        let deleted: Bool
        let id: String
        let occurrenceStart: String?
        let originalStartAt: String?
        let span: String
        let title: String
        let calendarID: String
        let calendarTitle: String

        private enum CodingKeys: String, CodingKey {
            case deleted, id, span, title
            case occurrenceStart = "occurrence_start"
            case originalStartAt = "original_start_at"
            case calendarID = "calendar_id"
            case calendarTitle = "calendar_title"
        }
    }

    private struct CalendarOutput: Codable, Sendable {
        let id: String
        let title: String
        let sourceID: String
        let sourceTitle: String
        let sourceType: String
        let colorHex: String?
        let isEditable: Bool
        let isSubscribed: Bool

        init(_ calendar: CalendarRecord) {
            id = calendar.id
            title = calendar.title
            sourceID = calendar.source.id
            sourceTitle = calendar.source.title
            sourceType = calendar.source.type.rawValue
            colorHex = calendar.colorHex
            isEditable = calendar.isEditable
            isSubscribed = calendar.isSubscribed
        }

        private enum CodingKeys: String, CodingKey {
            case id, title
            case sourceID = "source_id"
            case sourceTitle = "source_title"
            case sourceType = "source_type"
            case colorHex = "color_hex"
            case isEditable = "is_editable"
            case isSubscribed = "is_subscribed"
        }
    }

    private struct EventOutput: Codable, Sendable {
        let id: String
        let externalID: String?
        let calendarID: String
        let calendarTitle: String
        let title: String?
        let startAt: String
        let endAt: String
        let isAllDay: Bool
        let status: String
        let availability: String
        let location: String?
        let url: String?
        let notes: String?
        let structuredLocation: CalendarStructuredLocation?
        let timeZone: String?
        let createdAt: String?
        let modifiedAt: String?
        let alarms: [AlarmOutput]
        let recurrenceRules: [RecurrenceOutput]
        let hasAlarms: Bool
        let isRecurring: Bool
        let listTitle: String
        let startDate: String?
        let endDate: String?
        let occurrenceStart: String?
        let originalStartAt: String?
        let isDetached: Bool?
        let organizer: ParticipantOutput?
        let attendees: [ParticipantOutput]

        init(_ event: CalendarEvent) {
            id = calendarOpaqueID(event)
            externalID = event.externalID
            calendarID = event.identity.calendarID
            calendarTitle = event.calendarTitle
            title = event.title
            isAllDay = event.isAllDay
            startAt = Self.wireDate(event.startAt, isAllDay: isAllDay)
            endAt = Self.wireDate(event.endAt, isAllDay: isAllDay)
            status = event.status.rawValue
            availability = event.availability.rawValue
            location = event.location
            url = event.url?.absoluteString
            notes = event.notes
            structuredLocation = event.structuredLocation
            timeZone = event.timeZoneIdentifier
            createdAt = event.createdAt.map(MCPToolSupport.iso8601)
            modifiedAt = event.modifiedAt.map(MCPToolSupport.iso8601)
            alarms = event.alarms.map(AlarmOutput.init)
            recurrenceRules = event.recurrenceRules.map(RecurrenceOutput.init)
            hasAlarms = event.hasAlarms
            isRecurring = event.isRecurring
            listTitle = event.calendarTitle
            let eventTimeZone = event.timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? .current
            startDate = event.isAllDay ? Self.dateOnly(event.startAt, timeZone: eventTimeZone) : nil
            endDate = event.isAllDay ? Self.dateOnly(event.endAt, timeZone: eventTimeZone) : nil
            occurrenceStart = event.identity.occurrence.map { MCPToolSupport.iso8601($0.occurrenceStart) }
            originalStartAt = event.identity.occurrence.map { MCPToolSupport.iso8601($0.originalStart) }
            isDetached = event.identity.occurrence?.isDetached
            organizer = event.organizer.map(ParticipantOutput.init)
            attendees = event.attendees.map(ParticipantOutput.init)
        }

        private static func wireDate(_ date: Date, isAllDay: Bool) -> String {
            MCPToolSupport.iso8601(date)
        }

        private static func dateOnly(_ date: Date, timeZone: TimeZone) -> String {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = timeZone
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.string(from: date)
        }

        private enum CodingKeys: String, CodingKey {
            case id, title, status, availability, location, url, notes, organizer, attendees, alarms
            case externalID = "external_id"
            case calendarID = "calendar_id"
            case calendarTitle = "calendar_title"
            case startAt = "start_at"
            case endAt = "end_at"
            case isAllDay = "is_all_day"
            case modifiedAt = "modified_at"
            case structuredLocation = "structured_location"
            case timeZone = "time_zone"
            case createdAt = "created_at"
            case recurrenceRules = "recurrence_rules"
            case hasAlarms = "has_alarms"
            case isRecurring = "is_recurring"
            case listTitle = "list_title"
            case startDate = "start_date"
            case endDate = "end_date"
            case occurrenceStart = "occurrence_start"
            case originalStartAt = "original_start_at"
            case isDetached = "is_detached"
        }
    }

    private struct AlarmOutput: Codable, Sendable {
        let type: String
        let minutes: Int?
        let at: String?
        let proximity: String?
        let locationTitle: String?
        let latitude: Double?
        let longitude: Double?
        let radius: Double?
        let action: String
        let emailAddress: String?
        let soundName: String?

        init(_ alarm: CalendarAlarm) {
            type = alarm.kind.rawValue
            minutes = alarm.relativeOffsetMinutes.map { Int((-1 * $0).rounded()) }
            at = alarm.absoluteAt.map(MCPToolSupport.iso8601)
            proximity = alarm.proximity?.rawValue
            locationTitle = alarm.locationTitle
            latitude = alarm.latitude
            longitude = alarm.longitude
            radius = alarm.radius
            action = alarm.action.rawValue
            emailAddress = alarm.emailAddress
            soundName = alarm.soundName
        }
        private enum CodingKeys: String, CodingKey {
            case type, minutes, at, proximity, latitude, longitude, radius, action
            case locationTitle = "location_title"
            case emailAddress = "email_address"
            case soundName = "sound_name"
        }
    }

    private struct RecurrenceOutput: Codable, Sendable {
        let frequency: String
        let interval: Int
        let byDay: [String]
        let byMonthDay: [Int]
        let byMonth: [Int]
        let byWeekNo: [Int]
        let byYearDay: [Int]
        let bySetPos: [Int]
        let firstDayOfWeek: String?
        let endAt: String?
        let occurrenceCount: Int?

        init(_ rule: CalendarRecurrenceRule) {
            frequency = rule.frequency.rawValue
            interval = rule.interval
            let codes: [CalendarWeekday: String] = [
                .sunday: "SU", .monday: "MO", .tuesday: "TU", .wednesday: "WE", .thursday: "TH", .friday: "FR",
                .saturday: "SA",
            ]
            byDay = rule.daysOfTheWeek.map { ($0.weekNumber == 0 ? "" : String($0.weekNumber)) + codes[$0.day]! }
            byMonthDay = rule.daysOfTheMonth
            byMonth = rule.monthsOfTheYear
            byWeekNo = rule.weeksOfTheYear
            byYearDay = rule.daysOfTheYear
            bySetPos = rule.setPositions
            firstDayOfWeek = rule.firstDayOfTheWeek?.rawValue
            if case .endDate(let date)? = rule.end { endAt = MCPToolSupport.iso8601(date) } else { endAt = nil }
            if case .occurrenceCount(let count)? = rule.end { occurrenceCount = count } else { occurrenceCount = nil }
        }
        private enum CodingKeys: String, CodingKey {
            case frequency, interval
            case byDay = "by_day"
            case byMonthDay = "by_month_day"
            case byMonth = "by_month"
            case byWeekNo = "by_week_no"
            case byYearDay = "by_year_day"
            case bySetPos = "by_set_pos"
            case firstDayOfWeek = "first_day_of_week"
            case endAt = "end_at"
            case occurrenceCount = "occurrence_count"
        }
    }

    private struct ParticipantOutput: Codable, Sendable {
        let name: String?
        let email: String?
        let url: String?
        let status: String
        let role: String
        let type: String
        let isCurrentUser: Bool

        init(_ participant: CalendarParticipant) {
            name = participant.name
            email = participant.email
            url = participant.url?.absoluteString
            status = participant.status.rawValue
            role = participant.role.rawValue
            type = participant.type.rawValue
            isCurrentUser = participant.isCurrentUser
        }

        private enum CodingKeys: String, CodingKey {
            case name, email, url, status, role, type
            case isCurrentUser = "is_current_user"
        }
    }

    private struct BusyWindowOutput: Codable, Sendable {
        let startAt: String
        let endAt: String
        let eventCount: Int
        let events: [BusyEventOutput]

        init(_ window: CalendarBusyWindow, events: [String: CalendarEvent]) {
            startAt = MCPToolSupport.iso8601(window.startAt)
            endAt = MCPToolSupport.iso8601(window.endAt)
            self.events = window.eventIDs.compactMap { events[$0] }.map(BusyEventOutput.init)
            eventCount = self.events.count
        }

        init(start: Date, end: Date, events: [CalendarEvent]) {
            startAt = MCPToolSupport.iso8601(start)
            endAt = MCPToolSupport.iso8601(end)
            self.events = events.map(BusyEventOutput.init)
            eventCount = self.events.count
        }

        private enum CodingKeys: String, CodingKey {
            case startAt = "start_at"
            case endAt = "end_at"
            case eventCount = "event_count"
            case events
        }
    }

    private struct TimeWindowOutput: Codable, Sendable {
        let startAt: String
        let endAt: String
        init(start: Date, end: Date) { startAt = MCPToolSupport.iso8601(start); endAt = MCPToolSupport.iso8601(end) }
        private enum CodingKeys: String, CodingKey { case startAt = "start_at"; case endAt = "end_at" }
    }

    private struct BusyEventOutput: Codable, Sendable {
        let id: String
        let occurrenceStart: String?
        let originalStartAt: String?
        let title: String
        let startAt: String
        let endAt: String
        let isAllDay: Bool
        let availability: String
        let calendarID: String
        let calendarTitle: String
        init(_ event: CalendarEvent) {
            id = calendarOpaqueID(event);
            occurrenceStart = event.identity.occurrence.map { MCPToolSupport.iso8601($0.occurrenceStart) }
            originalStartAt = event.identity.occurrence.map { MCPToolSupport.iso8601($0.originalStart) }
            title = event.title ?? ""; startAt = MCPToolSupport.iso8601(event.startAt);
            endAt = MCPToolSupport.iso8601(event.endAt)
            isAllDay = event.isAllDay; availability = event.availability.rawValue
            calendarID = event.identity.calendarID; calendarTitle = event.calendarTitle
        }
        private enum CodingKeys: String, CodingKey {
            case id, title, availability
            case occurrenceStart = "occurrence_start"; case originalStartAt = "original_start_at"
            case startAt = "start_at"; case endAt = "end_at"; case isAllDay = "is_all_day"
            case calendarID = "calendar_id"; case calendarTitle = "calendar_title"
        }
    }

    private nonisolated static var readTools: [Tool] {
        [
            Tool(
                name: listCalendarsToolName, title: "List calendars",
                description: "Lists calendars with opaque IDs and editability metadata.", inputSchema: emptySchema,
                annotations: readAnnotations("List calendars"), outputSchema: calendarListSchema),
            Tool(
                name: fetchEventsToolName, title: "Fetch calendar events",
                description: "Fetches calendar events with date range, calendar, and event filters.",
                inputSchema: querySchema, annotations: readAnnotations("Fetch calendar events"),
                outputSchema: eventListSchema),
            Tool(
                name: getEventToolName, title: "Get calendar event",
                description: "Gets one event by opaque ID and optional recurring occurrence.",
                inputSchema: identitySchema, annotations: readAnnotations("Get calendar event"),
                outputSchema: eventSchema),
            Tool(
                name: freeBusyToolName, title: "Get calendar free/busy",
                description: "Returns merged busy windows for a date range.", inputSchema: freeBusyInputSchema,
                annotations: readAnnotations("Get calendar free/busy"), outputSchema: freeBusyOutputSchema),
        ]
    }

    private nonisolated static var writeTools: [Tool] {
        [
            Tool(
                name: createEventToolName, title: "Create calendar event", description: "Creates a calendar event.",
                inputSchema: createSchema,
                annotations: .init(
                    title: "Create calendar event", readOnlyHint: false, destructiveHint: false, idempotentHint: false,
                    openWorldHint: true), outputSchema: eventSchema),
            Tool(
                name: updateEventToolName, title: "Update calendar event",
                description:
                    "Updates one event or this and future recurring occurrences. Null clears location, URL, or notes.",
                inputSchema: updateSchema,
                annotations: .init(
                    title: "Update calendar event", readOnlyHint: false, destructiveHint: true, idempotentHint: true,
                    openWorldHint: true), outputSchema: eventSchema),
            Tool(
                name: deleteEventToolName, title: "Delete calendar event",
                description: "Deletes one event or this and future recurring occurrences.", inputSchema: deleteSchema,
                annotations: .init(
                    title: "Delete calendar event", readOnlyHint: false, destructiveHint: true, idempotentHint: false,
                    openWorldHint: true),
                outputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "deleted": .object(["type": .string("boolean")]),
                        "id": .object(["type": .string("string")]),
                        "occurrence_start": dateSchema, "original_start_at": dateSchema,
                        "span": .object(["type": .string("string")]),
                        "title": .object(["type": .string("string")]),
                        "calendar_id": .object(["type": .string("string")]),
                        "calendar_title": .object(["type": .string("string")]),
                    ]),
                    "required": .array([
                        .string("deleted"), .string("id"), .string("span"), .string("title"),
                        .string("calendar_id"), .string("calendar_title"),
                    ]), "additionalProperties": .bool(false),
                ])),
        ]
    }

    private nonisolated static func readAnnotations(_ title: String) -> Tool.Annotations {
        .init(title: title, readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false)
    }

    private nonisolated static var emptySchema: Value {
        .object(["type": .string("object"), "additionalProperties": .bool(false)])
    }
    private nonisolated static var dateSchema: Value {
        .object(["type": .string("string"), "description": .string("ISO 8601 date-time or local YYYY-MM-DD date.")])
    }
    private nonisolated static var calendarIDsSchema: Value {
        return .object([
            "type": .string("array"), "items": .object(["type": .string("string")]), "minItems": .int(1),
            "uniqueItems": .bool(true),
        ])
    }
    private nonisolated static var identityProperties: [String: Value] {
        ["id": .object(["type": .string("string")]), "occurrence_start": dateSchema, "original_start_at": dateSchema]
    }
    private nonisolated static var identitySchema: Value {
        .object([
            "type": .string("object"), "properties": .object(identityProperties), "required": .array([.string("id")]),
            "additionalProperties": .bool(false),
        ])
    }
    private nonisolated static var queryProperties: [String: Value] {
        [
            "from": dateSchema, "to": dateSchema, "calendar_ids": calendarIDsSchema,
            "list_names": calendarIDsSchema,
            "include_all_day": .object(["type": .string("boolean")]),
            "status": .object([
                "type": .string("string"),
                "enum": .array([.string("none"), .string("tentative"), .string("confirmed"), .string("canceled")]),
            ]),
            "availability": .object([
                "type": .string("string"),
                "enum": .array([
                    .string("busy"), .string("free"), .string("tentative"), .string("unavailable"),
                ]),
            ]),
            "has_alarms": .object(["type": .string("boolean")]),
            "is_recurring": .object(["type": .string("boolean")]), "query": .object(["type": .string("string")]),
        ]
    }
    private nonisolated static var querySchema: Value {
        .object([
            "type": .string("object"), "properties": .object(queryProperties),
            "additionalProperties": .bool(false),
        ])
    }
    private nonisolated static var freeBusyInputSchema: Value {
        var properties = queryProperties
        properties.removeValue(forKey: "status")
        properties.removeValue(forKey: "availability")
        properties.removeValue(forKey: "is_recurring")
        properties.removeValue(forKey: "has_alarms")
        properties.removeValue(forKey: "query")
        properties["include_tentative"] = .object(["type": .string("boolean")])
        return .object([
            "type": .string("object"), "properties": .object(properties),
            "required": .array([.string("from"), .string("to")]), "additionalProperties": .bool(false),
        ])
    }
    private nonisolated static var eventProperties: [String: Value] {
        [
            "id": .object(["type": .string("string")]), "calendar_id": .object(["type": .string("string")]),
            "external_id": .object(["type": .string("string")]),
            "calendar_title": .object(["type": .string("string")]),
            "title": .object(["type": .string("string")]),
            "start_at": dateSchema, "end_at": dateSchema, "is_all_day": .object(["type": .string("boolean")]),
            "start_date": dateSchema, "end_date": dateSchema,
            "status": .object(["type": .string("string")]), "availability": .object(["type": .string("string")]),
            "location": .object(["type": .string("string")]), "url": .object(["type": .string("string")]),
            "notes": .object(["type": .string("string")]),
            "structured_location": .object(["type": .string("object")]),
            "time_zone": .object(["type": .string("string")]), "created_at": dateSchema,
            "modified_at": dateSchema, "occurrence_start": dateSchema, "original_start_at": dateSchema,
            "is_detached": .object(["type": .string("boolean")]),
            "alarms": .object(["type": .string("array"), "items": .object(["type": .string("object")])]),
            "recurrence_rules": .object([
                "type": .string("array"), "items": .object(["type": .string("object")]),
            ]),
            "has_alarms": .object(["type": .string("boolean")]),
            "is_recurring": .object(["type": .string("boolean")]),
            "list_title": .object(["type": .string("string")]),
            "organizer": participantSchema,
            "attendees": .object(["type": .string("array"), "items": participantSchema]),
        ]
    }
    private nonisolated static var participantSchema: Value {
        .object([
            "type": .string("object"),
            "properties": .object([
                "name": .object(["type": .string("string")]), "email": .object(["type": .string("string")]),
                "url": .object(["type": .string("string")]), "status": .object(["type": .string("string")]),
                "role": .object(["type": .string("string")]), "type": .object(["type": .string("string")]),
                "is_current_user": .object(["type": .string("boolean")]),
            ]), "required": .array([.string("status"), .string("role"), .string("type"), .string("is_current_user")]),
            "additionalProperties": .bool(false),
        ])
    }
    private nonisolated static var eventSchema: Value {
        .object([
            "type": .string("object"), "properties": .object(eventProperties),
            "required": .array([
                .string("id"), .string("calendar_id"), .string("start_at"), .string("end_at"), .string("is_all_day"),
                .string("status"), .string("availability"), .string("attendees"), .string("alarms"),
                .string("recurrence_rules"), .string("has_alarms"), .string("is_recurring"), .string("list_title"),
            ]), "additionalProperties": .bool(false),
        ])
    }
    private nonisolated static var eventListSchema: Value {
        .object([
            "type": .string("object"),
            "properties": .object(["events": .object(["type": .string("array"), "items": eventSchema])]),
            "required": .array([.string("events")]), "additionalProperties": .bool(false),
        ])
    }
    private nonisolated static var calendarListSchema: Value {
        .object([
            "type": .string("object"),
            "properties": .object([
                "calendars": .object(["type": .string("array"), "items": .object(["type": .string("object")])])
            ]), "required": .array([.string("calendars")]), "additionalProperties": .bool(false),
        ])
    }
    private nonisolated static var freeBusyOutputSchema: Value {
        let window = Value.object([
            "type": .string("object"),
            "properties": .object([
                "start_at": dateSchema, "end_at": dateSchema,
                "event_count": .object(["type": .string("integer")]),
                "events": .object(["type": .string("array"), "items": .object(["type": .string("object")])]),
            ]),
            "required": .array([.string("start_at"), .string("end_at"), .string("event_count"), .string("events")]),
            "additionalProperties": .bool(false),
        ])
        let free = Value.object([
            "type": .string("object"), "properties": .object(["start_at": dateSchema, "end_at": dateSchema]),
            "required": .array([.string("start_at"), .string("end_at")]), "additionalProperties": .bool(false),
        ])
        return .object([
            "type": .string("object"),
            "properties": .object([
                "from": dateSchema, "to": dateSchema,
                "busy": .object(["type": .string("array"), "items": window]),
                "free": .object(["type": .string("array"), "items": free]),
                "conflicts": .object(["type": .string("array"), "items": window]),
            ]),
            "required": .array([
                .string("from"), .string("to"), .string("busy"), .string("free"), .string("conflicts"),
            ]), "additionalProperties": .bool(false),
        ])
    }
    private nonisolated static var createSchema: Value {
        .object([
            "type": .string("object"),
            "properties": .object([
                "calendar_id": .object(["type": .string("string")]), "list_name": .object(["type": .string("string")]),
                "title": .object(["type": .string("string")]),
                "start_at": dateSchema, "end_at": dateSchema, "is_all_day": .object(["type": .string("boolean")]),
                "availability": .object(["type": .string("string")]), "location": .object(["type": .string("string")]),
                "url": .object(["type": .string("string"), "format": .string("uri")]),
                "notes": .object(["type": .string("string")]),
                "time_zone": .object(["type": .string("string")]), "alarms": alarmsSchema,
                "recurrence": recurrenceSchema,
            ]), "required": .array([.string("title"), .string("start_at"), .string("end_at")]),
            "additionalProperties": .bool(false),
        ])
    }
    private nonisolated static var updateSchema: Value {
        var properties = identityProperties.merging([
            "title": .object(["type": .array([.string("string"), .string("null")])]), "start_at": dateSchema,
            "end_at": dateSchema, "calendar_id": .object(["type": .string("string")]),
            "list_name": .object(["type": .string("string")]),
            "is_all_day": .object(["type": .string("boolean")]), "availability": .object(["type": .string("string")]),
            "location": .object(["type": .array([.string("string"), .string("null")])]),
            "url": .object(["type": .array([.string("string"), .string("null")])]),
            "notes": .object(["type": .array([.string("string"), .string("null")])]),
            "time_zone": .object(["type": .array([.string("string"), .string("null")])]),
            "alarms": .object(["anyOf": .array([alarmsSchema, .object(["type": .string("null")])])]),
            "recurrence": .object(["anyOf": .array([recurrenceSchema, .object(["type": .string("null")])])]),
            "span": .object([
                "type": .string("string"), "enum": .array([.string("this_event"), .string("future_events")]),
            ]),
        ]) { _, new in new }
        properties["title"] = .object(["type": .string("string")])
        return .object([
            "type": .string("object"), "properties": .object(properties), "required": .array([.string("id")]),
            "additionalProperties": .bool(false),
        ])
    }
    private nonisolated static var deleteSchema: Value {
        var properties = identityProperties
        properties["span"] = .object([
            "type": .string("string"), "enum": .array([.string("this_event"), .string("future_events")]),
        ])
        properties["confirm"] = .object(["type": .string("boolean"), "const": .bool(true)])
        return .object([
            "type": .string("object"), "properties": .object(properties),
            "required": .array([.string("id"), .string("confirm")]), "additionalProperties": .bool(false),
        ])
    }

    private nonisolated static var alarmsSchema: Value {
        let email: Value = .object(["type": .string("string"), "format": .string("email")])
        return .object([
            "type": .string("array"), "maxItems": .int(20),
            "items": .object([
                "oneOf": .array([
                    .object([
                        "type": .string("object"),
                        "properties": .object([
                            "type": .object(["const": .string("relative")]),
                            "minutes": .object([
                                "type": .string("integer"), "minimum": .int(0), "maximum": .int(525_600),
                            ]), "email_address": email,
                        ]),
                        "required": .array([.string("type"), .string("minutes")]), "additionalProperties": .bool(false),
                    ]),
                    .object([
                        "type": .string("object"),
                        "properties": .object([
                            "type": .object(["const": .string("absolute")]), "at": dateSchema, "email_address": email,
                        ]),
                        "required": .array([.string("type"), .string("at")]), "additionalProperties": .bool(false),
                    ]),
                    .object([
                        "type": .string("object"),
                        "properties": .object([
                            "type": .object(["const": .string("proximity")]),
                            "proximity": .object(["enum": .array([.string("enter"), .string("leave")])]),
                            "location_title": .object(["type": .string("string")]),
                            "latitude": .object(["type": .string("number"), "minimum": .int(-90), "maximum": .int(90)]),
                            "longitude": .object([
                                "type": .string("number"), "minimum": .int(-180), "maximum": .int(180),
                            ]), "radius": .object(["type": .string("number"), "exclusiveMinimum": .int(0)]),
                            "email_address": email,
                        ]),
                        "required": .array([
                            .string("type"), .string("location_title"), .string("latitude"), .string("longitude"),
                        ]), "additionalProperties": .bool(false),
                    ]),
                ])
            ]),
        ])
    }

    private nonisolated static var recurrenceSchema: Value {
        .object([
            "type": .string("object"),
            "properties": .object([
                "frequency": .object([
                    "enum": .array([.string("daily"), .string("weekly"), .string("monthly"), .string("yearly")])
                ]),
                "interval": .object(["type": .string("integer"), "minimum": .int(1), "maximum": .int(Int(Int32.max))]),
                "by_day": .object([
                    "type": .string("array"), "items": .object(["type": .string("string")]), "uniqueItems": .bool(true),
                ]),
                "by_month_day": integerArraySchema(-31, 31), "by_month": integerArraySchema(1, 12),
                "by_week_no": integerArraySchema(-53, 53), "by_year_day": integerArraySchema(-366, 366),
                "by_set_pos": integerArraySchema(-366, 366), "end_at": dateSchema,
                "occurrence_count": .object(["type": .string("integer"), "minimum": .int(1)]),
            ]), "required": .array([.string("frequency")]), "additionalProperties": .bool(false),
        ])
    }

    private nonisolated static func integerArraySchema(_ minimum: Int, _ maximum: Int) -> Value {
        .object([
            "type": .string("array"),
            "items": .object(["type": .string("integer"), "minimum": .int(minimum), "maximum": .int(maximum)]),
            "uniqueItems": .bool(true), "maxItems": .int(366),
        ])
    }
}

private nonisolated func calendarOpaqueID(_ event: CalendarEvent) -> String {
    struct Wire: Codable {
        let eventID: String
        let calendarID: String
        let sourceID: String
        let isDetached: Bool
    }
    let wire = Wire(
        eventID: event.identity.eventID, calendarID: event.identity.calendarID,
        sourceID: event.identity.sourceID, isDetached: event.identity.occurrence?.isDetached ?? false)
    return (try? JSONEncoder().encode(wire).base64EncodedString()) ?? event.identity.stableID
}
