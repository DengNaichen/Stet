import ActivityKit
import Foundation
import OSLog

@MainActor
protocol MicrophoneLiveActivityManaging: AnyObject {
    func ensureActive() async
    func endAll() async
}

@MainActor
final class MicrophoneLiveActivityManager: MicrophoneLiveActivityManaging {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "NaichengDeng.StetMobile",
        category: "MicrophoneLiveActivity"
    )

    private var activeActivity: Activity<StetMicrophoneActivityAttributes>?

    func ensureActive() async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            activeActivity = nil
            Self.logger.info("Live Activities are disabled")
            return
        }

        let existingActivities = Activity<StetMicrophoneActivityAttributes>.activities
        if let existingActivity = existingActivities.first {
            activeActivity = existingActivity
            await endDuplicates(existingActivities.dropFirst())
            Self.logger.debug("Reusing microphone Live Activity id=\(existingActivity.id, privacy: .public)")
            return
        }

        do {
            let content = ActivityContent(
                state: StetMicrophoneActivityAttributes.ContentState(isMicrophoneActive: true),
                staleDate: nil
            )
            let activity = try Activity.request(
                attributes: StetMicrophoneActivityAttributes(),
                content: content,
                pushType: nil
            )
            activeActivity = activity
            Self.logger.info("Started microphone Live Activity id=\(activity.id, privacy: .public)")
        } catch {
            activeActivity = nil
            Self.logger.error(
                "Failed to start microphone Live Activity: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    func endAll() async {
        let activities = Activity<StetMicrophoneActivityAttributes>.activities
        activeActivity = nil

        for activity in activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }

        if !activities.isEmpty {
            Self.logger.info("Ended \(activities.count, privacy: .public) microphone Live Activities")
        }
    }

    private func endDuplicates(
        _ duplicates: ArraySlice<Activity<StetMicrophoneActivityAttributes>>
    ) async {
        for duplicate in duplicates {
            await duplicate.end(nil, dismissalPolicy: .immediate)
        }

        if !duplicates.isEmpty {
            Self.logger.info("Removed \(duplicates.count, privacy: .public) duplicate microphone Live Activities")
        }
    }
}

@MainActor
final class NoOpMicrophoneLiveActivityManager: MicrophoneLiveActivityManaging {
    func ensureActive() async {}
    func endAll() async {}
}
