#if os(macOS)
    import Combine
    import Foundation

    nonisolated protocol MeetingRecordingControlling: Sendable {
        func setPhaseHandler(_ handler: @escaping @MainActor @Sendable (MacMeetingRecordingPhase) -> Void) async
        func currentPhase() async -> MacMeetingRecordingPhase
        func start(expectedMeeting: ExpectedMeeting, separateSpeakers: Bool) async
        func toggle(separateSpeakers: Bool) async
    }

    /// Coordinates recording with scheduled meetings and publishes the phase used by the app UI.
    @MainActor
    final class MacMeetingWorkflowController: ObservableObject {
        @Published private(set) var phase: MacMeetingRecordingPhase = .idle

        private let recording: (any MeetingRecordingControlling)?
        private let expectedMeetings: (any ExpectedMeetingServing)?
        private let publishLivePhase: (MacMeetingRecordingPhase) -> Void
        private let notifyPhase: (MacMeetingRecordingPhase, MacMeetingRecordingPhase) async -> Void
        private let now: () -> Date
        private let prepareSpeakers: () async -> Bool?
        private var isPreparing = false
        private var activeExpectedMeetingID: UUID?

        init(
            recording: (any MeetingRecordingControlling)?,
            expectedMeetings: (any ExpectedMeetingServing)?,
            publishLivePhase: @escaping (MacMeetingRecordingPhase) -> Void,
            notifyPhase: @escaping (MacMeetingRecordingPhase, MacMeetingRecordingPhase) async -> Void,
            now: @escaping () -> Date = Date.init,
            prepareSpeakers: @escaping () async -> Bool? = { false }
        ) {
            self.recording = recording
            self.expectedMeetings = expectedMeetings
            self.publishLivePhase = publishLivePhase
            self.notifyPhase = notifyPhase
            self.now = now
            self.prepareSpeakers = prepareSpeakers
        }

        var isBusy: Bool {
            switch phase {
            case .starting, .recording, .processing, .separatingSpeakers, .transcribing: true
            case .idle, .failed: false
            }
        }

        func restoreReminders() {
            guard let expectedMeetings else { return }
            Task { await expectedMeetings.restoreReminders() }
        }

        func observeRecording() async {
            await recording?.setPhaseHandler { [weak self] phase in
                self?.receive(phase)
            }
        }

        func toggle() {
            guard let recording else { return }
            if case .recording = phase {
                Task { await recording.toggle(separateSpeakers: false) }
                return
            }
            guard !isBusy, !isPreparing else { return }
            isPreparing = true
            Task {
                defer { isPreparing = false }
                guard let separateSpeakers = await prepareSpeakers() else { return }
                await recording.toggle(separateSpeakers: separateSpeakers)
            }
        }

        func startExpectedMeeting(id: UUID) {
            guard !isBusy, !isPreparing, let expectedMeetings, let recording else { return }
            let now = now
            isPreparing = true
            Task {
                defer { isPreparing = false }
                guard let meeting = await expectedMeetings.meeting(id: id),
                    meeting.status == .scheduled,
                    meeting.scheduledEndAt > now()
                else { return }
                guard let separateSpeakers = await prepareSpeakers() else { return }
                await recording.start(expectedMeeting: meeting, separateSpeakers: separateSpeakers)
                guard case .recording(_, let folderName) = await recording.currentPhase() else { return }
                self.activeExpectedMeetingID = id
                try? await expectedMeetings.markRecorded(id: id, meetingID: folderName)
            }
        }

        func skipExpectedMeeting(id: UUID) {
            guard let expectedMeetings else { return }
            Task { try? await expectedMeetings.skip(id: id) }
        }

        private func receive(_ newPhase: MacMeetingRecordingPhase) {
            let previous = phase
            phase = newPhase
            publishLivePhase(newPhase)
            if previous.isProcessing,
                newPhase == .idle || newPhase.isFailure,
                let id = activeExpectedMeetingID,
                let expectedMeetings
            {
                activeExpectedMeetingID = nil
                Task { try? await expectedMeetings.markCompleted(id: id) }
            }
            let notifyPhase = notifyPhase
            Task { await notifyPhase(previous, newPhase) }
        }
    }

    private extension MacMeetingRecordingPhase {
        var isFailure: Bool {
            if case .failed = self { return true }
            return false
        }
    }
    extension MacMeetingRecordingRuntime: MeetingRecordingControlling {}
#endif
