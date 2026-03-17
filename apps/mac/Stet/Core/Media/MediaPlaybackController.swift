#if os(macOS)
import AppKit
import Darwin
import Foundation

private let mediaRemotePlayCommand: UInt32 = 0
private let mediaRemotePauseCommand: UInt32 = 1

private typealias MediaRemoteSendCommand = @convention(c) (UInt32, Optional<AnyObject>) -> Bool
private typealias MediaRemoteIsPlaying = @convention(c) (DispatchQueue, @escaping (Bool) -> Void) -> Void

@MainActor
protocol MediaPlaybackControlling: AnyObject {
    func pausePlaybackIfNeeded()
    func resumePlaybackIfNeeded()
}

@MainActor
final class MacMediaPlaybackController: MediaPlaybackControlling {
    struct MediaRemoteClient {
        let send: @Sendable (UInt32) -> Bool
        let isPlaying: @Sendable () -> Bool
    }

    struct Dependencies {
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

    private let dependencies: Dependencies
    private let systemAudioMuter: any SystemAudioMuting
    private var didPausePlayback = false
    private var didMuteSystemAudio = false
    private lazy var mediaRemote = dependencies.loadMediaRemoteClient()

    init(
        systemAudioMuter: (any SystemAudioMuting)? = nil,
        callbackQueue: DispatchQueue = DispatchQueue(label: "Stet.media-remote"),
        dependencies: Dependencies? = nil
    ) {
        self.systemAudioMuter = systemAudioMuter ?? SystemAudioMuteController()
        self.dependencies = dependencies ?? .live(callbackQueue: callbackQueue)
    }

    func pausePlaybackIfNeeded() {
        didPausePlayback = false
        didMuteSystemAudio = systemAudioMuter.activateMuteIfNeeded()

        if let mediaRemote {
            guard mediaRemote.isPlaying() else {
                return
            }

            didPausePlayback = mediaRemote.send(mediaRemotePauseCommand)
            if didPausePlayback {
                return
            }
        }

        didPausePlayback = dependencies.sendMediaKey()
    }

    func resumePlaybackIfNeeded() {
        let shouldResumePlayback = didPausePlayback
        didPausePlayback = false

        if didMuteSystemAudio {
            systemAudioMuter.restoreMuteIfNeeded()
            didMuteSystemAudio = false
        }

        guard shouldResumePlayback else {
            return
        }

        if let mediaRemote, mediaRemote.send(mediaRemotePlayCommand) {
            return
        }

        _ = dependencies.sendMediaKey()
    }

    nonisolated private static func loadMediaRemote() -> (send: MediaRemoteSendCommand, isPlaying: MediaRemoteIsPlaying)? {
        let frameworkPath = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"

        guard let handle = dlopen(frameworkPath, RTLD_NOW),
              let sendPointer = dlsym(handle, "MRMediaRemoteSendCommand"),
              let isPlayingPointer = dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying") else {
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
        var isPlaying = false

        callback(callbackQueue) { playing in
            isPlaying = playing
            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .now() + 2)
        return isPlaying
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
