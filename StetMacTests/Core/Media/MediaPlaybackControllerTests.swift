#if os(macOS)
    import Foundation
    import Testing

    @testable import Stet

    @MainActor
    @Suite("Media Playback Controller", .serialized)
    struct MediaPlaybackControllerTests {
        @Test func nonPlayingMediaDoesNotSendPauseOrResumeCommands() async {
            let commands = CommandLog()
            let queue = DispatchQueue(label: "media-test")
            let subject = MacMediaPlaybackController(
                operationQueue: queue,
                dependencies: .init(
                    loadMediaRemoteClient: {
                        .init(
                            send: {
                                commands.append($0); return true
                            }, isPlaying: { false })
                    },
                    sendMediaKey: {
                        commands.append(100); return true
                    }
                )
            )
            subject.pausePlaybackIfNeeded()
            await drain(queue)
            subject.resumePlaybackIfNeeded()
            await drain(queue)
            #expect(commands.values.isEmpty)
        }

        @Test func fallbackMediaKeyPauseAndResumeRemainAvailable() async {
            let commands = CommandLog()
            let queue = DispatchQueue(label: "media-test")
            let subject = MacMediaPlaybackController(
                operationQueue: queue,
                dependencies: .init(
                    loadMediaRemoteClient: { nil },
                    sendMediaKey: {
                        commands.append(100); return true
                    }
                )
            )
            subject.pausePlaybackIfNeeded()
            await drain(queue)
            subject.resumePlaybackIfNeeded()
            await drain(queue)
            #expect(commands.values == [100, 100])
        }

        @Test func slowPlaybackQueryDoesNotBlockMainActor() async {
            let queue = DispatchQueue(label: "media-test")
            let subject = MacMediaPlaybackController(
                operationQueue: queue,
                dependencies: .init(
                    loadMediaRemoteClient: {
                        .init(
                            send: { _ in true },
                            isPlaying: {
                                #expect(!Thread.isMainThread)
                                Thread.sleep(forTimeInterval: 0.2)
                                return true
                            })
                    },
                    sendMediaKey: { true }
                )
            )
            let start = ContinuousClock.now
            subject.pausePlaybackIfNeeded()
            #expect(start.duration(to: .now) < .milliseconds(100))
            await drain(queue)
        }

        @Test func endingCaptureDuringQueryDoesNotPausePlaybackLater() async {
            let commands = CommandLog()
            let queue = DispatchQueue(label: "media-test")
            let (started, continuation) = AsyncStream<Void>.makeStream()
            let releaseQuery = DispatchSemaphore(value: 0)
            let subject = MacMediaPlaybackController(
                operationQueue: queue,
                dependencies: .init(
                    loadMediaRemoteClient: {
                        .init(
                            send: {
                                commands.append($0); return true
                            },
                            isPlaying: {
                                continuation.yield(())
                                _ = releaseQuery.wait(timeout: .now() + 2)
                                return true
                            })
                    },
                    sendMediaKey: {
                        commands.append(100); return true
                    }
                )
            )
            subject.pausePlaybackIfNeeded()
            var iterator = started.makeAsyncIterator()
            await iterator.next()
            subject.resumePlaybackIfNeeded()
            releaseQuery.signal()
            await drain(queue)
            #expect(commands.values.isEmpty)
        }

        private func drain(_ queue: DispatchQueue) async {
            await withCheckedContinuation { continuation in
                queue.async { continuation.resume() }
            }
        }
    }

    nonisolated private final class CommandLog: @unchecked Sendable {
        private let lock = NSLock()
        private var commands: [UInt32] = []
        var values: [UInt32] { lock.withLock { commands } }
        func append(_ value: UInt32) { lock.withLock { commands.append(value) } }
    }
#endif
