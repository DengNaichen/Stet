#if os(macOS)
    import AVFoundation
    import Foundation
    import StetCore
    import Testing

    @testable import Stet

    @Suite("Mac Meeting Recording Runtime")
    @MainActor
    struct MacMeetingRecordingRuntimeTests {
        @Test func stopFinalizesAudioBeforeExistingProcessingCompletes() async throws {
            let root = TestSupport.temporaryDirectoryURL()
            defer { try? FileManager.default.removeItem(at: root) }
            let recording = RecordingFixture()
            let released = CallCounter()
            let hold = AsyncHold()
            let runtime = makeRuntime(
                root: root, recording: recording, released: released,
                diarize: { _ in
                    await hold.wait()
                    return []
                })
            await runtime.start()
            await runtime.toggle()
            #expect(await runtime.currentPhase() == .processing)
            #expect(released.value == 1)
            #expect(await recording.stopCount == 1)
            let directory = try #require(try MeetingRecordingStore(rootDirectory: root).sessionDirectories().first)
            let record = try MeetingSessionRecord.fromJSON(
                Data(contentsOf: directory.appendingPathComponent("session.json")))
            #expect(record.recordingStatus == "recorded")
            let audio = try AVAudioFile(forReading: directory.appendingPathComponent("audio.wav"))
            #expect(audio.length == 1_600)
            #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("microphone.wav").path))
            #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("system.wav").path))
            await runtime.toggle()
            #expect(await recording.startCount == 1)
            await hold.resume()
            await runtime.stop()
            #expect(await runtime.currentPhase() == .idle)
            let transcript = try String(contentsOf: directory.appendingPathComponent("transcript.md"), encoding: .utf8)
            #expect(transcript.contains("test meeting"))
        }

        @Test func recordingFailurePreservesAudioAndDoesNotStartProcessing() async throws {
            let root = TestSupport.temporaryDirectoryURL()
            defer { try? FileManager.default.removeItem(at: root) }
            let recording = RecordingFixture()
            let processed = CallCounter()
            let runtime = makeRuntime(
                root: root, recording: recording,
                diarize: { _ in
                    processed.increment()
                    return []
                })
            await runtime.start()
            await recording.fail("System audio disconnected.")
            #expect(
                await TestSupport.eventuallyAsync {
                    if case .failed = await runtime.currentPhase() { return true }
                    return false
                })
            #expect(processed.value == 0)
            #expect(await recording.stopCount == 1)
            let directory = try #require(try MeetingRecordingStore(rootDirectory: root).sessionDirectories().first)
            let record = try MeetingSessionRecord.fromJSON(
                Data(contentsOf: directory.appendingPathComponent("session.json")))
            #expect(record.recordingStatus == "failed")
            #expect(record.failureMessage == "System audio disconnected.")
            #expect(try AVAudioFile(forReading: directory.appendingPathComponent("audio.wav")).length == 1_600)
        }

        @Test func processingFailureDoesNotChangeSuccessfulRecordingStatus() async throws {
            let root = TestSupport.temporaryDirectoryURL()
            defer { try? FileManager.default.removeItem(at: root) }
            let runtime = makeRuntime(
                root: root, recording: RecordingFixture(),
                diarize: { _ in
                    throw MeetingRecordingError.failed("The test processor is unavailable.")
                })
            await runtime.start()
            await runtime.stop()
            let directory = try #require(try MeetingRecordingStore(rootDirectory: root).sessionDirectories().first)
            let record = try MeetingSessionRecord.fromJSON(
                Data(contentsOf: directory.appendingPathComponent("session.json")))
            #expect(record.recordingStatus == "recorded")
            if case .failed(let message) = await runtime.currentPhase() {
                #expect(message.hasPrefix("Recording saved."))
            } else {
                Issue.record("Expected the processing failure to be reported separately.")
            }
        }

        @Test func repeatedStartWhileHardwareIsStartingDoesNotCreateAnotherRecording() async throws {
            let root = TestSupport.temporaryDirectoryURL()
            defer { try? FileManager.default.removeItem(at: root) }
            let hold = AsyncHold()
            let recording = RecordingFixture(startHold: hold)
            let runtime = makeRuntime(root: root, recording: recording)
            let start = Task { await runtime.start() }
            #expect(await TestSupport.eventuallyAsync { await recording.startCount == 1 })
            #expect(await runtime.isBusy())
            #expect(await runtime.currentPhase() == .starting)
            await runtime.toggle()
            #expect(await recording.startCount == 1)
            await hold.resume()
            await start.value
            await runtime.stop()
        }

        @Test func failedStartReleasesExclusiveCaptureAndKeepsPartialAudio() async throws {
            let root = TestSupport.temporaryDirectoryURL()
            defer { try? FileManager.default.removeItem(at: root) }
            let recording = RecordingFixture(startError: "System audio permission denied.")
            let released = CallCounter()
            let runtime = makeRuntime(root: root, recording: recording, released: released)
            await runtime.start()
            #expect(released.value == 1)
            #expect(!((await runtime.isBusy())))
            if case .failed = await runtime.currentPhase() {
            } else {
                Issue.record("Expected a visible recording failure.")
            }
            let directory = try #require(try MeetingRecordingStore(rootDirectory: root).sessionDirectories().first)
            #expect(try AVAudioFile(forReading: directory.appendingPathComponent("microphone.wav")).length > 0)
        }

        @Test func expectedMeetingMetadataIsSavedWithRecording() async throws {
            let root = TestSupport.temporaryDirectoryURL()
            defer { try? FileManager.default.removeItem(at: root) }
            let date = Date(timeIntervalSince1970: 1_704_067_200)
            let expected = ExpectedMeeting(
                id: UUID(), source: "calendar", externalID: "event-1", scheduledStartAt: date,
                scheduledEndAt: date.addingTimeInterval(1_800), title: "Project sync",
                attendees: [MeetingAttendee(name: "Taylor", email: nil)], meetingURL: nil, notes: nil,
                sourceModifiedAt: nil, status: .scheduled, recordedMeetingID: nil
            )
            let runtime = makeRuntime(root: root, recording: RecordingFixture())
            await runtime.start(expectedMeeting: expected)
            await runtime.stop()
            let directory = try #require(try MeetingRecordingStore(rootDirectory: root).sessionDirectories().first)
            let record = try MeetingSessionRecord.fromJSON(
                Data(contentsOf: directory.appendingPathComponent("session.json")))
            #expect(record.metadata?.expectedMeetingID == expected.id)
            #expect(record.metadata?.title == "Project sync")
            #expect(record.recordingStatus == "recorded")
        }

        private func makeRuntime(
            root: URL, recording: RecordingFixture, released: CallCounter = CallCounter(),
            diarize: @escaping @Sendable ([Float]) async throws -> [PassiveDiarizedRegion] = { _ in [] }
        ) -> MacMeetingRecordingRuntime {
            MacMeetingRecordingRuntime(
                dependencies: .init(
                    store: MeetingRecordingStore(rootDirectory: root), makeRecording: { recording },
                    beginExclusiveCapture: {}, endExclusiveCapture: { released.increment() },
                    processor: MeetingSessionProcessor(
                        sampleRate: 16_000, diarize: diarize, transcribe: { _ in "test meeting" },
                        identify: { _ in PassiveSpeakerMatch(identity: .other, similarity: nil) }
                    ), now: { Date(timeIntervalSince1970: 1_704_067_200) }
                ))
        }
    }

    private actor RecordingFixture: MeetingAudioRecording {
        var startCount = 0
        var stopCount = 0
        private var session: MeetingAudioFileSession?
        private var failureHandler: (@Sendable (String) -> Void)?
        private var failure: String?
        private let startHold: AsyncHold?
        private let startError: String?

        init(startHold: AsyncHold? = nil, startError: String? = nil) {
            self.startHold = startHold
            self.startError = startError
        }

        func start(in directory: URL, onFailure: @escaping @Sendable (String) -> Void) async throws {
            startCount += 1
            await startHold?.wait()
            failureHandler = onFailure
            let session = try MeetingAudioFileSession(directory: directory, startTime: 100)
            self.session = session
            let format = try #require(
                AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false))
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_600))
            buffer.frameLength = 1_600
            let channel = try #require(buffer.floatChannelData?[0])
            channel.update(repeating: 0.25, count: 1_600)
            try session.append(buffer, source: .microphone, hostTime: 100)
            try session.append(buffer, source: .system, hostTime: 100)
            if let startError { throw MeetingRecordingError.failed(startError) }
        }

        func stop() async throws -> MeetingAudioRecordingResult {
            stopCount += 1
            let session = try #require(session)
            self.session = nil
            return try session.finish(at: 100.1, failure: failure)
        }

        func fail(_ message: String) {
            failure = message
            failureHandler?(message)
        }
    }

    private actor AsyncHold {
        private var continuation: CheckedContinuation<Void, Never>?
        private var resumed = false

        func wait() async {
            guard !resumed else { return }
            await withCheckedContinuation { continuation = $0 }
        }

        func resume() {
            resumed = true
            continuation?.resume()
            continuation = nil
        }
    }

    private final class CallCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        var value: Int { lock.withLock { count } }
        func increment() { lock.withLock { count += 1 } }
    }
#endif
