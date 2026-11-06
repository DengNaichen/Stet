#if os(macOS)
    import Combine
    import Foundation

    nonisolated protocol MeetingRecordingControlling: Sendable {
        func setPhaseHandler(_ handler: @escaping @MainActor @Sendable (MacMeetingRecordingPhase) -> Void) async
        func currentPhase() async -> MacMeetingRecordingPhase
        func start(expectedMeeting: ExpectedMeeting) async
        func toggle() async
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
        private var activeExpectedMeetingID: UUID?

        init(
            recording: (any MeetingRecordingControlling)?,
            expectedMeetings: (any ExpectedMeetingServing)?,
            publishLivePhase: @escaping (MacMeetingRecordingPhase) -> Void,
            notifyPhase: @escaping (MacMeetingRecordingPhase, MacMeetingRecordingPhase) async -> Void,
            now: @escaping () -> Date = Date.init
        ) {
            self.recording = recording
            self.expectedMeetings = expectedMeetings
            self.publishLivePhase = publishLivePhase
            self.notifyPhase = notifyPhase
            self.now = now
        }

        var isBusy: Bool {
            switch phase {
            case .starting, .recording, .processing: true
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
            Task { await recording.toggle() }
        }

        func startExpectedMeeting(id: UUID) {
            guard !isBusy, let expectedMeetings, let recording else { return }
            let now = now
            Task { [weak self] in
                guard let meeting = await expectedMeetings.meeting(id: id),
                    meeting.status == .scheduled,
                    meeting.scheduledEndAt > now()
                else { return }
                await recording.start(expectedMeeting: meeting)
                guard case .recording(_, let folderName) = await recording.currentPhase() else { return }
                self?.activeExpectedMeetingID = id
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
            if case .processing = previous,
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
