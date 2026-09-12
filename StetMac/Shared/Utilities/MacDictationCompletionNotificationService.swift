#if os(macOS)
    import Foundation
    import UserNotifications

    @MainActor
    final class MacDictationCompletionNotificationService: NSObject, UNUserNotificationCenterDelegate {
        static let shared = MacDictationCompletionNotificationService()

        static let expectedMeetingCategoryIdentifier = "stet.expected-meeting"
        static let startExpectedMeetingActionIdentifier = "stet.expected-meeting.start"
        static let skipExpectedMeetingActionIdentifier = "stet.expected-meeting.skip"
        static let expectedMeetingIDKey = "expectedMeetingID"

        private let center: UNUserNotificationCenter
        private var didInstallDelegate = false
        var onStartExpectedMeeting: (@MainActor @Sendable (UUID) -> Void)?
        var onSkipExpectedMeeting: (@MainActor @Sendable (UUID) -> Void)?

        init(center: UNUserNotificationCenter = .current()) {
            self.center = center
            super.init()
        }

        func installDelegateIfNeeded() {
            guard !didInstallDelegate else { return }
            center.delegate = self
            center.setNotificationCategories([
                UNNotificationCategory(
                    identifier: Self.expectedMeetingCategoryIdentifier,
                    actions: [
                        UNNotificationAction(
                            identifier: Self.startExpectedMeetingActionIdentifier,
                            title: String(localized: "Start Recording"),
                            options: [.foreground]
                        ),
                        UNNotificationAction(
                            identifier: Self.skipExpectedMeetingActionIdentifier,
                            title: String(localized: "Skip"),
                            options: []
                        ),
                    ],
                    intentIdentifiers: []
                )
            ])
            didInstallDelegate = true
        }

        func requestAuthorizationIfNeeded() async {
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .notDetermined else { return }
            _ = try? await center.requestAuthorization(options: [.alert])
        }

        func notifyMeetingPhase(
            from previous: MacMeetingRecordingPhase,
            to phase: MacMeetingRecordingPhase
        ) async {
            guard
                let payload = MacMeetingRecordingNotification.payload(from: previous, to: phase)
            else { return }

            let content = UNMutableNotificationContent()
            content.title = payload.title
            if let body = payload.body {
                content.body = body
            }
            await post(content, identifier: MacMeetingRecordingNotification.requestIdentifier)
        }

        private func post(_ content: UNMutableNotificationContent, identifier: String) async {
            await requestAuthorizationIfNeeded()
            let settings = await center.notificationSettings()
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                break
            default:
                return
            }

            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: nil
            )
            try? await center.add(request)
        }

        func scheduleExpectedMeeting(_ meeting: ExpectedMeeting) async {
            let now = Date()
            guard meeting.status == .scheduled, meeting.scheduledEndAt > now else {
                center.removePendingNotificationRequests(withIdentifiers: [meeting.reminderIdentifier])
                return
            }
            await requestAuthorizationIfNeeded()
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                return
            }

            let content = UNMutableNotificationContent()
            content.title = meeting.title?.nonPlaceholderMeetingTitle ?? String(localized: "Meeting soon")
            content.body = Self.expectedMeetingBody(meeting)
            content.categoryIdentifier = Self.expectedMeetingCategoryIdentifier
            content.userInfo = [Self.expectedMeetingIDKey: meeting.id.uuidString]

            let reminderDate = max(
                meeting.scheduledStartAt.addingTimeInterval(-5 * 60),
                now.addingTimeInterval(1)
            )
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: reminderDate
            )
            let request = UNNotificationRequest(
                identifier: meeting.reminderIdentifier,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            center.removePendingNotificationRequests(withIdentifiers: [meeting.reminderIdentifier])
            try? await center.add(request)
        }

        func cancelExpectedMeeting(_ meeting: ExpectedMeeting) {
            center.removePendingNotificationRequests(withIdentifiers: [meeting.reminderIdentifier])
            center.removeDeliveredNotifications(withIdentifiers: [meeting.reminderIdentifier])
        }

        nonisolated func userNotificationCenter(
            _ center: UNUserNotificationCenter,
            willPresent notification: UNNotification,
            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
        ) {
            completionHandler([.banner, .list])
        }

        nonisolated func userNotificationCenter(
            _ center: UNUserNotificationCenter,
            didReceive response: UNNotificationResponse,
            withCompletionHandler completionHandler: @escaping () -> Void
        ) {
            defer { completionHandler() }
            guard
                let rawID = response.notification.request.content.userInfo[Self.expectedMeetingIDKey]
                    as? String,
                let id = UUID(uuidString: rawID)
            else { return }

            Task { @MainActor [weak self] in
                switch response.actionIdentifier {
                case Self.startExpectedMeetingActionIdentifier,
                    UNNotificationDefaultActionIdentifier:
                    self?.onStartExpectedMeeting?(id)
                case Self.skipExpectedMeetingActionIdentifier:
                    self?.onSkipExpectedMeeting?(id)
                default:
                    break
                }
            }
        }

        nonisolated static func expectedMeetingBody(_ meeting: ExpectedMeeting) -> String {
            let time = meeting.scheduledStartAt.formatted(date: .omitted, time: .shortened)
            let names = meeting.attendees.map(\.name).filter { !$0.isEmpty }
            guard !names.isEmpty else {
                return String(format: String(localized: "Starts at %@."), time)
            }
            return String(
                format: String(localized: "Starts at %@ with %@."),
                time,
                names.joined(separator: ", ")
            )
        }
    }

    extension MacDictationCompletionNotificationService: ExpectedMeetingReminderScheduling {
        nonisolated func schedule(_ meeting: ExpectedMeeting) async {
            await scheduleExpectedMeeting(meeting)
        }

        nonisolated func cancel(_ meeting: ExpectedMeeting) async {
            await cancelExpectedMeeting(meeting)
        }
    }

    enum MacMeetingRecordingNotification {
        static let requestIdentifier = "stet.meeting.recording"

        struct Payload: Equatable, Sendable {
            var title: String
            var body: String?
        }

        static func payload(
            from previous: MacMeetingRecordingPhase,
            to phase: MacMeetingRecordingPhase
        ) -> Payload? {
            switch (previous, phase) {
            case (.recording, .processing):
                return Payload(
                    title: String(localized: "Meeting recording stopped"),
                    body: String(
                        localized: "The microphone is off. The transcript will be saved when it is ready."
                    )
                )
            case (_, .recording):
                return Payload(
                    title: String(localized: "Recording meeting"),
                    body: String(localized: "Press the shortcut again to stop.")
                )
            case (.processing, .idle):
                return Payload(title: String(localized: "Meeting saved"), body: nil)
            case (_, .failed(let message)):
                return Payload(title: String(localized: "Meeting failed"), body: message)
            default:
                return nil
            }
        }
    }

    private extension String {
        nonisolated var nonPlaceholderMeetingTitle: String? {
            let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed.caseInsensitiveCompare("(NO Title)") != .orderedSame else {
                return nil
            }
            return trimmed
        }
    }
#endif
