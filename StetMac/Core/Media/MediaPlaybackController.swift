#if os(macOS)
    import AppKit
    import Darwin
    import Foundation

    nonisolated private let mediaRemotePlayCommand: UInt32 = 0
    nonisolated private let mediaRemotePauseCommand: UInt32 = 1

    private typealias MediaRemoteSendCommand = @convention(c) (UInt32, Optional<AnyObject>) -> Bool
    private typealias MediaRemoteIsPlaying = @convention(c) (DispatchQueue, @escaping (Bool) -> Void) -> Void

    @MainActor
    protocol MediaPlaybackControlling: AnyObject {
        func pausePlaybackIfNeeded()
        func resumePlaybackIfNeeded()
    }

    @MainActor
    final class MacMediaPlaybackController: MediaPlaybackControlling {
        nonisolated struct MediaRemoteClient: Sendable {
            let send: @Sendable (UInt32) -> Bool
            let isPlaying: @Sendable () -> Bool
        }

        nonisolated struct Dependencies: Sendable {
            let loadMediaRemoteClient: @Sendable () -> MediaRemoteClient?
            let sendMediaKey: @Sendable () -> Bool

            static func live(callbackQueue: DispatchQueue) -> Self {
                Self(
                    loadMediaRemoteClient: {
                        guard let mediaRemote = MacMediaPlaybackController.loadMediaRemote() else {
                            return nil
                        }

                        return MediaRemoteClient(
                            send: { command in
                                mediaRemote.send(command, nil)
                            },
                            isPlaying: {
                                MacMediaPlaybackController.checkIsPlaying(
                                    using: mediaRemote.isPlaying,
                                    callbackQueue: callbackQueue
                                )
                            }
                        )
                    },
                    sendMediaKey: {
                        MacMediaPlaybackController.sendMediaKey()
                    }
                )
            }
        }

        private let worker: PlaybackWorker

        init(
            callbackQueue: DispatchQueue = DispatchQueue(label: "Stet.media-remote"),
            operationQueue: DispatchQueue = DispatchQueue(label: "Stet.media-playback", qos: .userInitiated),
            dependencies: Dependencies? = nil
        ) {
            worker = PlaybackWorker(
                queue: operationQueue,
                dependencies: dependencies ?? .live(callbackQueue: callbackQueue)
            )
        }

        func pausePlaybackIfNeeded() {
            worker.setPaused(true)
        }

        func resumePlaybackIfNeeded() {
            worker.setPaused(false)
        }

        // MediaRemote and osascript may block. Only this dedicated queue owns the
        // playback commands; neither MainActor nor the cooperative pool waits for them.
        nonisolated private final class PlaybackWorker: @unchecked Sendable {
            private let queue: DispatchQueue
            private let dependencies: Dependencies
            private let intentLock = NSLock()
            private var wantsPause = false
            private var didPausePlayback = false
            private var mediaRemote: MediaRemoteClient?
            private var didLoadMediaRemote = false

            init(queue: DispatchQueue, dependencies: Dependencies) {
                self.queue = queue
                self.dependencies = dependencies
            }

            func setPaused(_ paused: Bool) {
                intentLock.withLock { wantsPause = paused }
                queue.async { self.reconcilePlayback() }
            }

            private var shouldPause: Bool { intentLock.withLock { wantsPause } }

            private func reconcilePlayback() {
                dispatchPrecondition(condition: .onQueue(queue))
                if !didLoadMediaRemote {
                    mediaRemote = dependencies.loadMediaRemoteClient()
                    didLoadMediaRemote = true
                }
                if shouldPause {
                    guard !didPausePlayback else { return }
                    if let mediaRemote {
                        guard mediaRemote.isPlaying(), shouldPause else { return }
                        didPausePlayback = mediaRemote.send(mediaRemotePauseCommand)
                        if didPausePlayback { return }
                    }
                    guard shouldPause else { return }
                    didPausePlayback = dependencies.sendMediaKey()
                } else {
                    guard didPausePlayback else { return }
                    didPausePlayback = false
                    if let mediaRemote, mediaRemote.send(mediaRemotePlayCommand) { return }
                    _ = dependencies.sendMediaKey()
                }
            }
        }

        nonisolated private final class PlaybackQueryResult: @unchecked Sendable {
            private let lock = NSLock()
            private var isPlaying = false

            func set(_ value: Bool) { lock.withLock { isPlaying = value } }
            func get() -> Bool { lock.withLock { isPlaying } }
        }

        nonisolated private static func loadMediaRemote() -> (
            send: MediaRemoteSendCommand, isPlaying: MediaRemoteIsPlaying
        )? {
            let frameworkPath = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"

            guard let handle = dlopen(frameworkPath, RTLD_NOW),
                let sendPointer = dlsym(handle, "MRMediaRemoteSendCommand"),
                let isPlayingPointer = dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying")
            else {
                return nil
            }

            let send = unsafeBitCast(sendPointer, to: MediaRemoteSendCommand.self)
            let isPlaying = unsafeBitCast(isPlayingPointer, to: MediaRemoteIsPlaying.self)
            return (send: send, isPlaying: isPlaying)
        }

        nonisolated private static func checkIsPlaying(
            using callback: MediaRemoteIsPlaying,
            callbackQueue: DispatchQueue
        ) -> Bool {
            let semaphore = DispatchSemaphore(value: 0)
            let result = PlaybackQueryResult()

            callback(callbackQueue) { playing in
                result.set(playing)
                semaphore.signal()
            }

            _ = semaphore.wait(timeout: .now() + 2)
            return result.get()
        }

        nonisolated private static func sendMediaKey() -> Bool {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", #"tell application "System Events" to key code 100"#]

            do {
                try process.run()
                process.waitUntilExit()
                return process.terminationStatus == 0
            } catch {
                return false
            }
        }
    }
#endif
