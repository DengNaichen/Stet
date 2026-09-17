#if os(macOS)
    @preconcurrency import AVFoundation
    import FluidAudio
    import Foundation
    import StetCore

    nonisolated enum MacMeetingRecordingPhase: Equatable, Sendable {
        case idle
        case starting
        case recording(startedAt: Date, folderName: String)
        case processing
        case failed(String)
    }

    actor MacMeetingRecordingRuntime {
        // Completed recordings can use larger chunks without adding live-capture latency.
        nonisolated static var diarizationConfig: SortformerConfig { .efficientV2_1 }

        struct Dependencies: Sendable {
            var store: MeetingRecordingStore
            var makeRecording: @Sendable () -> any MeetingAudioRecording
            var beginExclusiveCapture: @Sendable () async -> Void
            var endExclusiveCapture: @Sendable () async -> Void
            var processor: MeetingSessionProcessor
            var now: @Sendable () -> Date
        }

        private let dependencies: Dependencies
        private var phase: MacMeetingRecordingPhase = .idle
        private var processingTask: Task<Void, Never>?
        private var session: ActiveSession?
        private var pendingExpectedMeeting: ExpectedMeeting?
        private var isStarting = false
        private var isStopping = false
        private var captureFailure: String?
        private var phaseHandler: @MainActor @Sendable (MacMeetingRecordingPhase) -> Void = { _ in }

        private struct ActiveSession {
            var id: UUID
            var directory: MeetingSessionDirectory
            var recording: any MeetingAudioRecording
            var startedAt: Date
            var metadata: MeetingMetadata?
        }

        init(dependencies: Dependencies) { self.dependencies = dependencies }

        func setPhaseHandler(_ handler: @escaping @MainActor @Sendable (MacMeetingRecordingPhase) -> Void) {
            phaseHandler = handler
        }

        func currentPhase() -> MacMeetingRecordingPhase { phase }

        func isBusy() -> Bool {
            if isStarting || isStopping { return true }
            switch phase {
            case .starting, .recording, .processing: return true
            case .idle, .failed: return false
            }
        }

        func toggle() async {
            guard !isStarting, !isStopping else { return }
            switch phase {
            case .recording: await requestStop()
            case .starting, .processing: break
            case .idle, .failed: await start()
            }
        }

        func start() async {
            guard !isBusy() else { return }
            isStarting = true
            captureFailure = nil
            await setPhase(.starting)
            var exclusive = false
            do {
                let startedAt = dependencies.now()
                let directory = try dependencies.store.makeSessionDirectory(startedAt: startedAt)
                let expectedMeeting = pendingExpectedMeeting
                let metadata = await MainActor.run { expectedMeeting.map(MeetingMetadata.init) }
                let active = ActiveSession(
                    id: UUID(), directory: directory, recording: dependencies.makeRecording(), startedAt: startedAt,
                    metadata: metadata
                )
                session = active
                pendingExpectedMeeting = nil
                await dependencies.beginExclusiveCapture()
                exclusive = true
                let sessionID = active.id
                try await active.recording.start(in: directory.url) { [weak self] message in
                    Task { await self?.recordingFailed(id: sessionID, message: message) }
                }
                try writeRecord(for: active, status: "recording", duration: 0, recordingStatus: "recording")
                await setPhase(.recording(startedAt: startedAt, folderName: directory.url.lastPathComponent))
                isStarting = false
                if captureFailure != nil { await requestStop() }
            } catch {
                if let active = session {
                    // The recorder also finalizes partial sources on a failed start.
                    _ = try? await active.recording.stop()
                    try? writeRecord(
                        for: active, status: "failed", duration: 0, recordingStatus: "failed",
                        failure: error.localizedDescription
                    )
                }
                session = nil
                pendingExpectedMeeting = nil
                if exclusive { await dependencies.endExclusiveCapture() }
                isStarting = false
                await setPhase(.failed("Recording failed: \(error.localizedDescription)"))
            }
        }

        func start(expectedMeeting: ExpectedMeeting) async {
            guard !isBusy() else { return }
            pendingExpectedMeeting = expectedMeeting
            await start()
        }

        func stop() async {
            await requestStop()
            await processingTask?.value
        }

        private func recordingFailed(id: UUID, message: String) async {
            guard session?.id == id else { return }
            captureFailure = message
            if !isStarting { await requestStop() }
        }

        private func requestStop() async {
            guard !isStarting, !isStopping, case .recording = phase, let active = session else { return }
            isStopping = true
            session = nil
            let endedAt = dependencies.now()
            do {
                let audio = try await active.recording.stop()
                let failure = captureFailure ?? audio.failureMessage
                captureFailure = nil
                try writeRecord(
                    for: active, status: failure == nil ? "processing" : "failed", duration: audio.duration,
                    recordingStatus: failure == nil ? "recorded" : "failed", failure: failure, endedAt: endedAt
                )
                await dependencies.endExclusiveCapture()
                if let failure {
                    await setPhase(.failed("Recording failed: \(failure)"))
                } else {
                    await setPhase(.processing)
                    processingTask = Task { await self.process(active, audio: audio, endedAt: endedAt) }
                }
            } catch {
                try? writeRecord(
                    for: active, status: "failed", duration: endedAt.timeIntervalSince(active.startedAt),
                    recordingStatus: "failed", failure: error.localizedDescription, endedAt: endedAt
                )
                await dependencies.endExclusiveCapture()
                await setPhase(
                    .failed("Could not finish the recording: \(error.localizedDescription). Source audio was kept."))
            }
            isStopping = false
        }

        private func process(_ active: ActiveSession, audio: MeetingAudioRecordingResult, endedAt: Date) async {
            do {
                // Existing processing starts only after all recording files have been finalized.
                let samples = try await Task.detached(priority: .utility) {
                    try Self.readSamples(at: audio.audioURL)
                }.value
                let turns = try await dependencies.processor.process(samples: samples)
                let markdown = MeetingTranscriptDocument.markdown(
                    startedAt: active.startedAt, endedAt: endedAt, turns: turns, metadata: active.metadata
                )
                try markdown.write(to: active.directory.transcriptURL, atomically: true, encoding: .utf8)
                try writeRecord(
                    for: active, status: "completed", duration: audio.duration, recordingStatus: "recorded",
                    endedAt: endedAt, speakerCount: Set(turns.map(\.speakerLabel)).count
                )
                await setPhase(.idle)
            } catch {
                let note = "Processing failed: \(error.localizedDescription). The recording was saved."
                let markdown = MeetingTranscriptDocument.markdown(
                    startedAt: active.startedAt, endedAt: endedAt, turns: [], metadata: active.metadata, note: note
                )
                try? markdown.write(to: active.directory.transcriptURL, atomically: true, encoding: .utf8)
                try? writeRecord(
                    for: active, status: "failed", duration: audio.duration, recordingStatus: "recorded",
                    failure: error.localizedDescription, endedAt: endedAt
                )
                await setPhase(.failed("Recording saved. Processing failed: \(error.localizedDescription)"))
            }
            processingTask = nil
        }

        nonisolated private static func readSamples(at url: URL) throws -> [Float] {
            let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
            guard file.length > 0, file.length <= Int64(UInt32.max),
                let buffer = AVAudioPCMBuffer(
                    pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))
            else { throw MeetingRecordingError.failed("The saved recording could not be loaded for processing.") }
            try file.read(into: buffer)
            guard let channel = buffer.floatChannelData?[0] else {
                throw AudioWavWriterError.unableToAccessOutputChannelData
            }
            return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        }

        private func setPhase(_ phase: MacMeetingRecordingPhase) async {
            self.phase = phase
            await phaseHandler(phase)
        }

        private func writeRecord(
            for active: ActiveSession, status: String, duration: Double, recordingStatus: String,
            failure: String? = nil, endedAt: Date? = nil, speakerCount: Int = 0
        ) throws {
            let record = MeetingSessionRecord(
                startedAt: active.startedAt, endedAt: endedAt, durationSeconds: duration, status: status,
                failureMessage: failure, speakerCount: speakerCount, metadata: active.metadata,
                recordingStatus: recordingStatus
            )
            try record.jsonData().write(to: active.directory.sessionURL, options: .atomic)
        }
    }

    extension MacMeetingRecordingRuntime {
        @MainActor
        static func live(
            beginExclusiveCapture: @escaping @Sendable () async -> Void,
            endExclusiveCapture: @escaping @Sendable () async -> Void
        ) -> MacMeetingRecordingRuntime {
            let identity = MacPassiveSpeakerIdentityRuntime(
                profileStore: SpeakerProfileStore(),
                modelManager: SpeakerEmbeddingModelManager()
            )
            let nano = try? FunASRNanoTranscriptionService()
            let processor = MeetingSessionProcessor(
                sampleRate: FluidAudioPassiveSpeechAnalyzer.sampleRate,
                prepareTranscription: {
                    guard let nano else { throw SpeechServiceError.failedToStart }
                    try await nano.acquireContextLease()
                },
                finishTranscription: {
                    await nano?.releaseContextLease()
                },
                diarize: { samples in
                    let analyzer = try await FluidAudioPassiveSpeechAnalyzer.load(
                        sortformerConfig: diarizationConfig
                    )
                    _ = try await analyzer.addAcceptedAudio(samples)
                    return try await analyzer.finalizeAcceptedAudio()
                },
                transcribe: { samples in
                    let url = try AudioWavWriter.writePCM16MonoWav(
                        samples: samples,
                        filePrefix: "stet-meeting-turn"
                    )
                    defer { try? FileManager.default.removeItem(at: url) }
                    guard let nano else { throw SpeechServiceError.failedToStart }
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
                    makeRecording: { MacMeetingAudioRecorder() },
                    beginExclusiveCapture: beginExclusiveCapture,
                    endExclusiveCapture: endExclusiveCapture,
                    processor: processor,
                    now: { Date() }
                )
            )
        }
    }
#endif
