#if os(macOS)
    import Foundation

    struct MacMeetingSnapshot {
        var meetingRecordingPhase: MacMeetingRecordingPhase
        var isCalendarMeetingsEnabled: Bool
        var calendarAuthorizationStatus: CalendarAuthorizationStatus
        var calendarSyncState: CalendarSyncState
        var selectedCalendarIDs: Set<String>

        var isMeetingBusy: Bool {
            switch meetingRecordingPhase {
            case .starting, .recording, .processing, .separatingSpeakers, .transcribing: true
            case .idle, .failed: false
            }
        }

        var meetingStatusText: String {
            switch meetingRecordingPhase {
            case .idle:
                return "Meeting recording idle"
            case .starting:
                return "Starting microphone and system audio recording"
            case .recording(_, let folderName):
                return "Recording meeting · \(folderName)"
            case .processing:
                return String(localized: "Recording saved · Preparing transcription")
            case .separatingSpeakers:
                return String(localized: "Recording saved · Separating speakers")
            case .transcribing:
                return String(localized: "Recording saved · Transcribing")
            case .failed(let message):
                return message
            }
        }

        var meetingMenuSymbolName: String {
            switch meetingRecordingPhase {
            case .recording:
                return "record.circle.fill"
            case .starting, .processing, .separatingSpeakers, .transcribing:
                return "hourglass"
            case .failed:
                return "exclamationmark.triangle"
            case .idle:
                return "record.circle"
            }
        }

        var meetingToggleTitle: String {
            switch meetingRecordingPhase {
            case .idle, .failed:
                return "Start Meeting Recording"
            case .starting:
                return "Starting meeting recording"
            case .recording:
                return "Stop Meeting Recording"
            case .processing, .separatingSpeakers, .transcribing:
                return "Processing meeting"
            }
        }

        var canToggleMeetingRecording: Bool {
            switch meetingRecordingPhase {
            case .starting, .processing, .separatingSpeakers, .transcribing:
                return false
            case .idle, .recording, .failed:
                return true
            }
        }

    }
#endif
