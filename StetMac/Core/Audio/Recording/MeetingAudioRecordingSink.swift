#if os(macOS)
    @preconcurrency import AVFoundation
    import Foundation

    /// Copies borrowed capture buffers into a bounded writer queue; no file I/O runs in capture callbacks.
    nonisolated final class MeetingAudioRecordingSink: @unchecked Sendable {
        private let queue = DispatchQueue(label: "Stet.MeetingAudio.writer", qos: .userInitiated)
        private let lock = NSLock()
        private let session: MeetingAudioFileSession
        private let onFailure: @Sendable (String) -> Void
        private var accepting = true
        private var pendingBytes = 0
        private var failure: String?
        private var lastMicrophoneBufferTime: TimeInterval
        private var watchdog: DispatchSourceTimer?
        private static let maximumPendingBytes = 8 * 1_024 * 1_024
        private static let microphoneTimeout: TimeInterval = 5

        init(directory: URL, startTime: TimeInterval, onFailure: @escaping @Sendable (String) -> Void) throws {
            session = try MeetingAudioFileSession(directory: directory, startTime: startTime)
            lastMicrophoneBufferTime = startTime
            self.onFailure = onFailure
        }

        func startMonitoring() {
            queue.async { [self] in
                let timer = DispatchSource.makeTimerSource(queue: self.queue)
                timer.schedule(deadline: .now() + Self.microphoneTimeout, repeating: 1)
                timer.setEventHandler { [weak self] in
                    guard let self else { return }
                    let overdue = self.lock.withLock {
                        self.accepting
                            && ProcessInfo.processInfo.systemUptime - self.lastMicrophoneBufferTime
                                > Self.microphoneTimeout
                    }
                    if overdue {
                        self.reportFailure(
                            "Microphone audio stopped. Check the selected input device. The recorded audio was kept.")
                    }
                }
                self.watchdog = timer
                timer.resume()
            }
        }

        func receive(_ input: AVAudioPCMBuffer, source: MeetingAudioSource, hostTime: TimeInterval) {
            let bytes = UnsafeMutableAudioBufferListPointer(input.mutableAudioBufferList)
                .reduce(0) { $0 + Int($1.mDataByteSize) }
            guard bytes > 0 else { return }
            lock.lock()
            guard accepting else { lock.unlock(); return }
            guard pendingBytes + bytes <= Self.maximumPendingBytes else {
                lock.unlock()
                reportFailure(
                    "Meeting audio could not be saved fast enough. Recording stopped and existing audio was kept.")
                return
            }
            guard let owned = Self.copy(input) else {
                lock.unlock()
                reportFailure("Could not copy meeting audio. Existing audio was kept.")
                return
            }
            pendingBytes += bytes
            if source == .microphone { lastMicrophoneBufferTime = ProcessInfo.processInfo.systemUptime }
            // finish takes this lock too, so every accepted buffer precedes finalization.
            queue.async {
                defer { self.lock.withLock { self.pendingBytes -= bytes } }
                do { try self.session.append(owned, source: source, hostTime: hostTime) } catch {
                    self.reportFailure("Could not save meeting audio: \(error.localizedDescription)")
                }
            }
            lock.unlock()
        }

        func reportFailure(_ message: String) {
            let shouldReport = lock.withLock { () -> Bool in
                guard failure == nil else { return false }
                failure = message
                let wasAccepting = accepting
                accepting = false
                return wasAccepting
            }
            if shouldReport { onFailure(message) }
        }

        func finish(at hostTime: TimeInterval) async throws -> MeetingAudioRecordingResult {
            try await withCheckedThrowingContinuation { continuation in
                lock.withLock {
                    accepting = false
                    queue.async {
                        self.watchdog?.cancel()
                        self.watchdog = nil
                        let failure = self.lock.withLock { self.failure }
                        do {
                            continuation.resume(returning: try self.session.finish(at: hostTime, failure: failure))
                        } catch { continuation.resume(throwing: error) }
                    }
                }
            }
        }

        private static func copy(_ input: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
            guard let output = AVAudioPCMBuffer(pcmFormat: input.format, frameCapacity: input.frameLength) else {
                return nil
            }
            output.frameLength = input.frameLength
            let source = UnsafeMutableAudioBufferListPointer(input.mutableAudioBufferList)
            let destination = UnsafeMutableAudioBufferListPointer(output.mutableAudioBufferList)
            guard source.count == destination.count else { return nil }
            for index in source.indices {
                guard let from = source[index].mData, let to = destination[index].mData,
                    source[index].mDataByteSize <= destination[index].mDataByteSize
                else { return nil }
                memcpy(to, from, Int(source[index].mDataByteSize))
            }
            return output
        }
    }
#endif
