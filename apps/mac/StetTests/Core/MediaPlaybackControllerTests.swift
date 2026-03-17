#if os(macOS)
import Foundation
import Testing

@testable import Stet

@MainActor
private final class FakeSystemAudioMuter: SystemAudioMuting {
    var shouldActivate = true
    private(set) var activateCallCount = 0
    private(set) var restoreCallCount = 0

    func activateMuteIfNeeded() -> Bool {
        activateCallCount += 1
        return shouldActivate
    }

    func restoreMuteIfNeeded() {
        restoreCallCount += 1
    }
}

@MainActor
@Suite("Media Playback Controller", .serialized)
struct MediaPlaybackControllerTests {
    @Test func nonPlayingMediaStillMutesSystemAudioDuringDictation() {
        let systemAudioMuter = FakeSystemAudioMuter()
        var sendCommandCount = 0
        var fallbackMediaKeyCount = 0
        let subject = MacMediaPlaybackController(
            systemAudioMuter: systemAudioMuter,
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

        #expect(systemAudioMuter.activateCallCount == 1)
        #expect(sendCommandCount == 0)
        #expect(fallbackMediaKeyCount == 0)

        subject.resumePlaybackIfNeeded()

        #expect(systemAudioMuter.restoreCallCount == 1)
        #expect(sendCommandCount == 0)
        #expect(fallbackMediaKeyCount == 0)
    }

    @Test func fallbackMediaKeyPauseAndResumeTracksSystemAudioMute() {
        let systemAudioMuter = FakeSystemAudioMuter()
        var fallbackMediaKeyCount = 0
        let subject = MacMediaPlaybackController(
            systemAudioMuter: systemAudioMuter,
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

        #expect(systemAudioMuter.activateCallCount == 1)
        #expect(systemAudioMuter.restoreCallCount == 1)
        #expect(fallbackMediaKeyCount == 2)
    }
}
#endif
