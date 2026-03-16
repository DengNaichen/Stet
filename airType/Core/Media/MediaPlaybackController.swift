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
    private let callbackQueue = DispatchQueue(label: "airType.media-remote")
    private var didPausePlayback = false
    private lazy var mediaRemote = loadMediaRemote()

    func pausePlaybackIfNeeded() {
        didPausePlayback = false

        if let mediaRemote {
            guard checkIsPlaying(using: mediaRemote.isPlaying) else {
                return
            }

            didPausePlayback = mediaRemote.send(mediaRemotePauseCommand, nil)
            if didPausePlayback {
                return
            }
        }

        didPausePlayback = sendMediaKey()
    }

    func resumePlaybackIfNeeded() {
        guard didPausePlayback else { return }
        didPausePlayback = false

        if let mediaRemote, mediaRemote.send(mediaRemotePlayCommand, nil) {
            return
        }

        _ = sendMediaKey()
    }

    private func loadMediaRemote() -> (send: MediaRemoteSendCommand, isPlaying: MediaRemoteIsPlaying)? {
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

    private func checkIsPlaying(using callback: MediaRemoteIsPlaying) -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        var isPlaying = false

        callback(callbackQueue) { playing in
            isPlaying = playing
            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .now() + 2)
        return isPlaying
    }

    private func sendMediaKey() -> Bool {
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
