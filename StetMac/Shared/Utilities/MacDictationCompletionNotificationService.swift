#if os(macOS)
    import Foundation
    import UserNotifications

    @MainActor
    protocol MacDictationCompletionNotifying: AnyObject {
        func notifyDictationCompleted() async
    }

    @MainActor
    final class MacDictationCompletionNotificationService: NSObject, MacDictationCompletionNotifying,
        UNUserNotificationCenterDelegate
    {
        static let shared = MacDictationCompletionNotificationService()
        static let requestIdentifier = "stet.dictation.completed"

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

        func notifyDictationCompleted() async {
            await requestAuthorizationIfNeeded()
            let settings = await center.notificationSettings()
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                break
            default:
                return
            }

            let content = UNMutableNotificationContent()
            content.title = String(localized: "Dictation complete")
            let request = UNNotificationRequest(
                identifier: Self.requestIdentifier,
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
#endif
