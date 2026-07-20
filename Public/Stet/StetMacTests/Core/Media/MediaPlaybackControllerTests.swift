#if os(macOS)
    import Foundation
    import Testing

    @testable import Stet

    @MainActor
    @Suite("Media Playback Controller", .serialized)
    struct MediaPlaybackControllerTests {
        @Test func nonPlayingMediaDoesNotSendPauseOrResumeCommands() {
            var sendCommandCount = 0
            var fallbackMediaKeyCount = 0
            let subject = MacMediaPlaybackController(
                dependencies: .init(
                    loadMediaRemoteClient: {
                        .init(
                            send: { _ in
                                sendCommandCount += 1
                                return true
                            },
                            isPlaying: {
                                false
                            }
                        )
                    },
                    sendMediaKey: {
                        fallbackMediaKeyCount += 1
                        return true
                    }
                )
            )

            subject.pausePlaybackIfNeeded()
            subject.resumePlaybackIfNeeded()

            #expect(sendCommandCount == 0)
            #expect(fallbackMediaKeyCount == 0)
        }

        @Test func fallbackMediaKeyPauseAndResumeRemainAvailable() {
            var fallbackMediaKeyCount = 0
            let subject = MacMediaPlaybackController(
                dependencies: .init(
                    loadMediaRemoteClient: {
                        nil
                    },
                    sendMediaKey: {
                        fallbackMediaKeyCount += 1
                        return true
                    }
                )
            )

            subject.pausePlaybackIfNeeded()
            subject.resumePlaybackIfNeeded()

            #expect(fallbackMediaKeyCount == 2)
        }
    }
#endif
