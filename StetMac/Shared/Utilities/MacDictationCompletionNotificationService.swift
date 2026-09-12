#if os(macOS)
    import Foundation
    import UserNotifications

    @MainActor
    final class MacDictationCompletionNotificationService: NSObject, UNUserNotificationCenterDelegate {
        static let shared = MacDictationCompletionNotificationService()

        private let center: UNUserNotificationCenter
        private var didInstallDelegate = false

        init(center: UNUserNotificationCenter = .current()) {
            self.center = center
            super.init()
        }

        func installDelegateIfNeeded() {
            guard !didInstallDelegate else { return }
            center.delegate = self
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

        nonisolated func userNotificationCenter(
            _ center: UNUserNotificationCenter,
            willPresent notification: UNNotification,
            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
        ) {
            completionHandler([.banner, .list])
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
#endif
