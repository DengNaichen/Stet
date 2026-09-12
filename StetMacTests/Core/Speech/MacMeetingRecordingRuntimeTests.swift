#if os(macOS)
    import Foundation
    import StetCore
    import Testing

    @testable import Stet

    @Suite("Mac Meeting Recording Runtime")
    struct MacMeetingRecordingRuntimeTests {
        @Test func stopWritesAudioTranscriptAndSessionWithoutRewrite() async throws {
            let root = TestSupport.temporaryDirectoryURL()
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let (stream, continuation) = AsyncStream<AudioCaptureFrame>.makeStream()
            let exclusive = CallCounter()
            let startedAt = Date(timeIntervalSince1970: 1_704_067_200)
            let runtime = MacMeetingRecordingRuntime(
                dependencies: MacMeetingRecordingRuntime.Dependencies(
                    store: MeetingRecordingStore(rootDirectory: root),
                    ensureCaptureRunning: {},
                    beginExclusiveCapture: { exclusive.increment() },
                    endExclusiveCapture: { exclusive.increment() },
                    makeFrameStream: { stream },
                    processor: MeetingSessionProcessor(
                        sampleRate: 16_000,
                        diarize: { _ in
                            [
                                PassiveDiarizedRegion(
                                    speakerTrack: 0,
                                    startSample: 0,
                                    endSample: 2,
                                    activityConfidence: 1,
                                    isOverlap: false
                                )
                            ]
                        },
                        transcribe: { _ in "hello from the room" },
                        identify: { _ in PassiveSpeakerMatch(identity: .self, similarity: 0.92) }
                    ),
                    now: { startedAt }
                )
            )

            await runtime.start()
            continuation.yield(
                AudioCaptureFrame(epoch: 1, startSample: 0, samples: [0.25, -0.25])
            )
            #expect(
                await TestSupport.eventuallyAsync {
                    await runtime.recordedSampleCount() == 2
                }
            )
            continuation.finish()
            await runtime.stop()

            #expect(await runtime.currentPhase() == .idle)
            #expect(exclusive.value == 2)

            let folders = try FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil
            ).filter(\.hasDirectoryPath)
            let folder = try #require(folders.first)
            let audio = folder.appendingPathComponent("audio.wav")
            let transcript = folder.appendingPathComponent("transcript.md")
            let session = folder.appendingPathComponent("session.json")
            #expect(FileManager.default.fileExists(atPath: audio.path))
            #expect(FileManager.default.fileExists(atPath: transcript.path))
            #expect(FileManager.default.fileExists(atPath: session.path))

            let markdown = try String(contentsOf: transcript, encoding: .utf8)
            #expect(markdown.contains("**Me**"))
            #expect(markdown.contains("hello from the room"))
            #expect(!markdown.localizedCaseInsensitiveContains("rewrite"))

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let record = try decoder.decode(
                MeetingSessionRecord.self,
                from: Data(contentsOf: session)
            )
            #expect(record.status == "completed")
        }

        @Test func expectedMeetingMetadataIsSavedWithRecording() async throws {
            let root = TestSupport.temporaryDirectoryURL()
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let (stream, continuation) = AsyncStream<AudioCaptureFrame>.makeStream()
            let startedAt = Date(timeIntervalSince1970: 1_704_067_200)
            let expected = ExpectedMeeting(
                id: UUID(),
                source: "calendar",
                externalID: "event-1",
                scheduledStartAt: startedAt,
                scheduledEndAt: startedAt.addingTimeInterval(1_800),
                title: "Project sync",
                attendees: [MeetingAttendee(name: "Taylor", email: nil)],
                meetingURL: nil,
                notes: nil,
                sourceModifiedAt: nil,
                status: .scheduled,
                recordedMeetingID: nil
            )
            let runtime = MacMeetingRecordingRuntime(
                dependencies: MacMeetingRecordingRuntime.Dependencies(
                    store: MeetingRecordingStore(rootDirectory: root),
                    ensureCaptureRunning: {},
                    beginExclusiveCapture: {},
                    endExclusiveCapture: {},
                    makeFrameStream: { stream },
                    processor: MeetingSessionProcessor(
                        sampleRate: 16_000,
                        diarize: { _ in [] },
                        transcribe: { _ in "" },
                        identify: { _ in PassiveSpeakerMatch(identity: .other, similarity: nil) }
                    ),
                    now: { startedAt }
                )
            )

            await runtime.start(expectedMeeting: expected)
            continuation.finish()
            await runtime.stop()

            let directory = try #require(
                try MeetingRecordingStore(rootDirectory: root).sessionDirectories().first
            )
            let session = try JSONDecoder.iso8601.decode(
                MeetingSessionRecord.self,
                from: Data(contentsOf: directory.appendingPathComponent("session.json"))
            )
            #expect(session.metadata?.expectedMeetingID == expected.id)
            #expect(session.metadata?.title == "Project sync")
            #expect(session.metadata?.attendees.first?.name == "Taylor")
        }

        @Test func stopCompletesWhileCaptureStreamKeepsProducing() async throws {
            let root = TestSupport.temporaryDirectoryURL()
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let (stream, continuation) = AsyncStream<AudioCaptureFrame>.makeStream()
            let exclusive = CallCounter()
            let runtime = MacMeetingRecordingRuntime(
                dependencies: MacMeetingRecordingRuntime.Dependencies(
                    store: MeetingRecordingStore(rootDirectory: root),
                    ensureCaptureRunning: {},
                    beginExclusiveCapture: { exclusive.increment() },
                    endExclusiveCapture: { exclusive.increment() },
                    makeFrameStream: { stream },
                    processor: MeetingSessionProcessor(
                        sampleRate: 16_000,
                        diarize: { _ in [] },
                        transcribe: { _ in "kept going" },
                        identify: { _ in PassiveSpeakerMatch(identity: .other, similarity: nil) }
                    ),
                    now: { Date(timeIntervalSince1970: 1_704_067_200) }
                )
            )

            await runtime.start()
            continuation.yield(
                AudioCaptureFrame(epoch: 1, startSample: 0, samples: [0.1, -0.1])
            )
            #expect(
                await TestSupport.eventuallyAsync {
                    await runtime.recordedSampleCount() == 2
                }
            )

            await runtime.stop()

            #expect(await runtime.currentPhase() == .idle)
            #expect(exclusive.value == 2)
            continuation.finish()
        }

        @Test func toggleDuringProcessingDoesNotStartAnotherMeeting() async throws {
            let root = TestSupport.temporaryDirectoryURL()
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let (stream, continuation) = AsyncStream<AudioCaptureFrame>.makeStream()
            let exclusive = CallCounter()
            let hold = AsyncHold()
            let runtime = MacMeetingRecordingRuntime(
                dependencies: MacMeetingRecordingRuntime.Dependencies(
                    store: MeetingRecordingStore(rootDirectory: root),
                    ensureCaptureRunning: {},
                    beginExclusiveCapture: { exclusive.increment() },
                    endExclusiveCapture: { exclusive.increment() },
                    makeFrameStream: { stream },
                    processor: MeetingSessionProcessor(
                        sampleRate: 16_000,
                        diarize: { _ in
                            await hold.wait()
                            return [
                                PassiveDiarizedRegion(
                                    speakerTrack: 0,
                                    startSample: 0,
                                    endSample: 2,
                                    activityConfidence: 1,
                                    isOverlap: false
                                )
                            ]
                        },
                        transcribe: { _ in "held" },
                        identify: { _ in PassiveSpeakerMatch(identity: .self, similarity: 0.9) }
                    ),
                    now: { Date(timeIntervalSince1970: 1_704_067_200) }
                )
            )

            await runtime.start()
            continuation.yield(
                AudioCaptureFrame(epoch: 1, startSample: 0, samples: [0.2, -0.2])
            )
            #expect(
                await TestSupport.eventuallyAsync {
                    await runtime.recordedSampleCount() == 2
                }
            )

            let firstToggle = Task { await runtime.toggle() }
            #expect(
                await TestSupport.eventuallyAsync {
                    await runtime.currentPhase() == .processing
                }
            )

            await runtime.toggle()
            await hold.waitUntilWaiting()
            await hold.resume()
            await firstToggle.value

            #expect(
                await TestSupport.eventuallyAsync {
                    await runtime.currentPhase() == .idle
                }
            )
            #expect(exclusive.value == 2)

            let folders = try FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil
            ).filter(\.hasDirectoryPath)
            #expect(folders.count == 1)
            continuation.finish()
        }

        @Test func stopReleasesExclusiveCaptureBeforeProcessingFinishes() async throws {
            let root = TestSupport.temporaryDirectoryURL()
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let (stream, continuation) = AsyncStream<AudioCaptureFrame>.makeStream()
            let exclusive = CallCounter()
            let hold = AsyncHold()
            let runtime = MacMeetingRecordingRuntime(
                dependencies: MacMeetingRecordingRuntime.Dependencies(
                    store: MeetingRecordingStore(rootDirectory: root),
                    ensureCaptureRunning: {},
                    beginExclusiveCapture: { exclusive.increment() },
                    endExclusiveCapture: { exclusive.increment() },
                    makeFrameStream: { stream },
                    processor: MeetingSessionProcessor(
                        sampleRate: 16_000,
                        diarize: { _ in
                            await hold.wait()
                            return []
                        },
                        transcribe: { _ in "held" },
                        identify: { _ in PassiveSpeakerMatch(identity: .other, similarity: nil) }
                    ),
                    now: { Date(timeIntervalSince1970: 1_704_067_200) }
                )
            )

            await runtime.start()
            continuation.yield(
                AudioCaptureFrame(epoch: 1, startSample: 0, samples: [0.2, -0.2])
            )
            #expect(
                await TestSupport.eventuallyAsync {
                    await runtime.recordedSampleCount() == 2
                }
            )

            let stopTask = Task { await runtime.toggle() }
            #expect(
                await TestSupport.eventuallyAsync {
                    await runtime.currentPhase() == .processing
                }
            )
            #expect(exclusive.value == 2)

            await hold.waitUntilWaiting()
            await hold.resume()
            await stopTask.value
            #expect(
                await TestSupport.eventuallyAsync {
                    await runtime.currentPhase() == .idle
                }
            )
            continuation.finish()
        }
    }

    private extension JSONDecoder {
        static var iso8601: JSONDecoder {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return decoder
        }
    }

    private actor AsyncHold {
        private var continuation: CheckedContinuation<Void, Never>?
        private var isWaiting = false

        func wait() async {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                self.isWaiting = true
            }
        }

        func waitUntilWaiting() async {
            while !isWaiting {
                await Task.yield()
            }
        }

        func resume() {
            guard let continuation else { return }
            self.continuation = nil
            isWaiting = false
            continuation.resume()
        }
    }

    private final class CallCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0

        var value: Int {
            lock.withLock { count }
        }

        func increment() {
            lock.withLock { count += 1 }
        }
    }
#endif
