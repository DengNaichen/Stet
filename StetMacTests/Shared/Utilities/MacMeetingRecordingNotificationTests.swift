#if os(macOS)
    import Foundation
    import Testing

    @testable import Stet

    @Suite("Mac Meeting Recording Notification")
    struct MacMeetingRecordingNotificationTests {
        @Test func startPostsRecordingBanner() {
            let payload = MacMeetingRecordingNotification.payload(
                from: .idle,
                to: .recording(startedAt: Date(), folderName: "2024-01-01")
            )

            #expect(payload?.title == String(localized: "Recording meeting"))
            #expect(payload?.body == String(localized: "Press the shortcut again to stop."))
        }

        @Test func stopPostsMicrophoneOffBannerBeforeTranscriptIsReady() {
            let payload = MacMeetingRecordingNotification.payload(
                from: .recording(startedAt: Date(), folderName: "2024-01-01"),
                to: .processing
            )

            #expect(payload?.title == String(localized: "Meeting recording stopped"))
            #expect(
                payload?.body
                    == String(
                        localized: "The microphone is off. The transcript will be saved when it is ready."
                    )
            )
        }

        @Test func completedProcessingPostsSavedBanner() {
            let payload = MacMeetingRecordingNotification.payload(
                from: .processing,
                to: .idle
            )

            #expect(payload?.title == String(localized: "Meeting saved"))
            #expect(payload?.body == nil)
        }

        @Test func idleDoesNotPostABanner() {
            #expect(MacMeetingRecordingNotification.payload(from: .idle, to: .idle) == nil)
        }
    }
#endif
