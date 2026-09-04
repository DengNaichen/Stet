#if os(macOS)
    import Foundation
    import os
    import StetCore

    nonisolated enum MacMeetingRecordingPhase: Equatable, Sendable {
        case idle
        case recording(startedAt: Date, folderName: String)
        case processing
        case failed(String)
    }

    actor MacMeetingRecordingRuntime {
        struct Dependencies: Sendable {
            var store: MeetingRecordingStore
            var ensureCaptureRunning: @Sendable () async throws -> Void
            var beginExclusiveCapture: @Sendable () async -> Void
            var endExclusiveCapture: @Sendable () async -> Void
            var makeFrameStream: @Sendable () async -> AsyncStream<AudioCaptureFrame>
            var processor: MeetingSessionProcessor
            var now: @Sendable () -> Date
        }

        private let dependencies: Dependencies
        private let logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "com.openwhispr.Stet",
            category: "MeetingRecording"
        )
        private var phase: MacMeetingRecordingPhase = .idle
        private var frameTask: Task<Void, Never>?
        private var processingTask: Task<Void, Never>?
        private var session: ActiveSession?
        private var phaseHandler: @MainActor @Sendable (MacMeetingRecordingPhase) -> Void = { _ in }

        private struct ActiveSession {
            var directory: MeetingSessionDirectory
            var writer: MeetingAudioWriter
            var samples: [Float]
            var startedAt: Date
        }

        init(dependencies: Dependencies) {
            self.dependencies = dependencies
        }

        func setPhaseHandler(_ handler: @escaping @MainActor @Sendable (MacMeetingRecordingPhase) -> Void) {
            phaseHandler = handler
        }

        func currentPhase() -> MacMeetingRecordingPhase {
            phase
        }

        func isBusy() -> Bool {
            switch phase {
            case .recording, .processing:
                return true
            case .idle, .failed:
                return false
            }
        }

        func recordedSampleCount() -> Int {
            session?.samples.count ?? 0
        }

        func toggle() async {
            switch phase {
            case .recording:
                await requestStop()
            case .processing:
                break
            case .idle, .failed:
                await start()
            }
        }

        func start() async {
            guard !isBusy() else { return }
            var didBeginExclusive = false
            do {
                try await dependencies.ensureCaptureRunning()
                await dependencies.beginExclusiveCapture()
                didBeginExclusive = true
                let startedAt = dependencies.now()
                let directory = try dependencies.store.makeSessionDirectory(startedAt: startedAt)
                let writer = try MeetingAudioWriter(url: directory.audioURL)
                session = ActiveSession(
                    directory: directory,
                    writer: writer,
                    samples: [],
                    startedAt: startedAt
                )
                let folderName = directory.url.lastPathComponent
                await setPhase(.recording(startedAt: startedAt, folderName: folderName))
                let stream = await dependencies.makeFrameStream()
                frameTask = Task { [weak self] in
                    for await frame in stream {
                        guard !Task.isCancelled else { break }
                        await self?.append(frame.samples)
                    }
                }
            } catch {
                logger.error("Meeting start failed: \(error.localizedDescription, privacy: .public)")
                if didBeginExclusive {
                    await dependencies.endExclusiveCapture()
                }
                await setPhase(.failed(error.localizedDescription))
            }
        }

        func stop() async {
            await requestStop()
            if let processingTask {
                await processingTask.value
            }
        }

        private func requestStop() async {
            guard case .recording = phase, let active = session else { return }
            session = nil
            frameTask?.cancel()
            frameTask = nil
            logger.info("Meeting stop requested")
            await setPhase(.processing)
            let samples = active.samples
            let directory = active.directory
            let startedAt = active.startedAt
            processingTask = Task {
                await self.completeStoppedSession(
                    samples: samples,
                    directory: directory,
                    startedAt: startedAt
                )
            }
        }

        private func completeStoppedSession(
            samples: [Float],
            directory: MeetingSessionDirectory,
            startedAt: Date
        ) async {
            let endedAt = dependencies.now()

            do {
                let turns = try await dependencies.processor.process(samples: samples)
                let markdown = MeetingTranscriptDocument.markdown(
                    startedAt: startedAt,
                    endedAt: endedAt,
                    turns: turns
                )
                try markdown.write(to: directory.transcriptURL, atomically: true, encoding: .utf8)
                let record = MeetingSessionRecord(
                    startedAt: startedAt,
                    endedAt: endedAt,
                    durationSeconds: endedAt.timeIntervalSince(startedAt),
                    status: "completed",
                    failureMessage: nil,
                    speakerCount: Set(turns.map(\.speakerLabel)).count
                )
                try writeRecord(record, to: directory.sessionURL)
                await setPhase(.idle)
            } catch {
                logger.error("Meeting processing failed: \(error.localizedDescription, privacy: .public)")
                let markdown = MeetingTranscriptDocument.markdown(
                    startedAt: startedAt,
                    endedAt: endedAt,
                    turns: [],
                    note: "Processing failed: \(error.localizedDescription). The audio file was kept."
                )
                try? markdown.write(to: directory.transcriptURL, atomically: true, encoding: .utf8)
                let record = MeetingSessionRecord(
                    startedAt: startedAt,
                    endedAt: endedAt,
                    durationSeconds: endedAt.timeIntervalSince(startedAt),
                    status: "failed",
                    failureMessage: error.localizedDescription,
                    speakerCount: 0
                )
                try? writeRecord(record, to: directory.sessionURL)
                await setPhase(.failed(error.localizedDescription))
            }

            processingTask = nil
            await dependencies.endExclusiveCapture()
        }

        private func append(_ samples: [Float]) {
            guard var active = session else { return }
            do {
                try active.writer.append(samples)
            } catch {
                logger.error("Meeting audio write failed: \(error.localizedDescription, privacy: .public)")
            }
            active.samples.append(contentsOf: samples)
            session = active
        }

        private func setPhase(_ phase: MacMeetingRecordingPhase) async {
            self.phase = phase
            await phaseHandler(phase)
        }

        private func writeRecord(_ record: MeetingSessionRecord, to url: URL) throws {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(record).write(to: url)
        }
    }

    extension MacMeetingRecordingRuntime {
        static func live(
            captureService: MacAudioCaptureService,
            beginExclusiveCapture: @escaping @Sendable () async -> Void,
            endExclusiveCapture: @escaping @Sendable () async -> Void
        ) -> MacMeetingRecordingRuntime {
            let identity = MacPassiveSpeakerIdentityRuntime(
                profileStore: SpeakerProfileStore(),
                modelManager: SpeakerEmbeddingModelManager()
            )
            let processor = MeetingSessionProcessor(
                sampleRate: FluidAudioPassiveSpeechAnalyzer.sampleRate,
                diarize: { samples in
                    let analyzer = try await FluidAudioPassiveSpeechAnalyzer.load()
                    _ = try await analyzer.addAcceptedAudio(samples)
                    return try await analyzer.finalizeAcceptedAudio()
                },
                transcribe: { samples in
                    let url = try AudioWavWriter.writePCM16MonoWav(
                        samples: samples,
                        filePrefix: "stet-meeting-turn"
                    )
                    defer { try? FileManager.default.removeItem(at: url) }
                    let nano = try FunASRNanoTranscriptionService()
                    return try await nano.transcribe(
                        audioFileAt: url,
                        languageCode: nil,
                        prompt: nil,
                        audioDurationSeconds: Double(samples.count)
                            / Double(FluidAudioPassiveSpeechAnalyzer.sampleRate)
                    ).text
                },
                identify: { try await identity.identify($0) }
            )
            return MacMeetingRecordingRuntime(
                dependencies: Dependencies(
                    store: MeetingRecordingStore(),
                    ensureCaptureRunning: {
                        try await captureService.startContinuousCapture()
                    },
                    beginExclusiveCapture: beginExclusiveCapture,
                    endExclusiveCapture: endExclusiveCapture,
                    makeFrameStream: {
                        await captureService.makeAudioCaptureFrameStream()
                    },
                    processor: processor,
                    now: { Date() }
                )
            )
        }
    }
#endif
