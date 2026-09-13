#if os(macOS)
    import Foundation

    nonisolated struct CalendarMeetingMapper: Sendable {
        private static let placeholderTitles: Set<String> = [
            "(no title)", "(no subject)", "no title", "untitled event",
        ]
        private static let meetingHosts = [
            "zoom.us", "teams.microsoft.com", "meet.google.com", "webex.com",
            "feishu.cn", "larksuite.com", "whereby.com", "around.co",
        ]

        func map(_ event: CalendarEvent) -> ExpectedMeetingInput? {
            guard !event.isAllDay,
                event.status != .canceled,
                event.endAt > event.startAt,
                !currentUserDeclined(event)
            else { return nil }

            return ExpectedMeetingInput(
                source: "calendar:\(event.identity.sourceID):\(event.identity.calendarID)",
                externalID: event.identity.stableID,
                scheduledStartAt: event.startAt,
                scheduledEndAt: event.endAt,
                title: normalizedTitle(event.title),
                attendees: event.attendees.compactMap(mapAttendee),
                meetingURL: meetingURL(for: event),
                notes: event.notes,
                sourceModifiedAt: event.modifiedAt,
                status: .scheduled
            )
        }

        func map(_ events: [CalendarEvent]) -> [ExpectedMeetingInput] {
            events.compactMap(map)
        }

        private func normalizedTitle(_ title: String?) -> String? {
            guard let title = title?.trimmingCharacters(in: .whitespacesAndNewlines),
                !title.isEmpty,
                !Self.placeholderTitles.contains(title.lowercased())
            else { return nil }
            return title
        }

        private func currentUserDeclined(_ event: CalendarEvent) -> Bool {
            event.attendees.contains { $0.isCurrentUser && $0.status == .declined }
        }

        private func mapAttendee(_ participant: CalendarParticipant) -> MeetingAttendee? {
            guard !participant.isCurrentUser else { return nil }
            let name = participant.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            let email = participant.email?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let displayName = name?.isEmpty == false ? name : email, !displayName.isEmpty else {
                return nil
            }
            return MeetingAttendee(name: displayName, email: email?.isEmpty == false ? email : nil)
        }

        private func meetingURL(for event: CalendarEvent) -> URL? {
            if let url = event.url, isWebURL(url) { return url }
            for text in [event.location, event.notes].compactMap({ $0 }) {
                if let url = URLs(in: text).first(where: isMeetingURL) { return url }
            }
            return nil
        }

        private func URLs(in text: String) -> [URL] {
            let pattern = #"(?i)https?://[^\s<>\[\](){}\"']+"#
            guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
            let range = NSRange(text.startIndex..., in: text)
            return expression.matches(in: text, range: range).compactMap { match in
                guard let range = Range(match.range, in: text) else { return nil }
                let value = String(text[range]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;!?:"))
                return URL(string: value)
            }
        }

        private func isWebURL(_ url: URL) -> Bool {
            guard let scheme = url.scheme?.lowercased() else { return false }
            return scheme == "https" || scheme == "http"
        }

        private func isMeetingURL(_ url: URL) -> Bool {
            guard isWebURL(url), let host = url.host()?.lowercased() else { return false }
            return Self.meetingHosts.contains { host == $0 || host.hasSuffix(".\($0)") }
        }
    }
#endif
