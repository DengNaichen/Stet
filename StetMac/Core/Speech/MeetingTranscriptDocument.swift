#if os(macOS)
    import Foundation
    import StetCore

    struct MeetingTranscriptTurn: Equatable, Sendable {
        let startSeconds: Double
        let endSeconds: Double
        let speakerLabel: String
        let text: String
        let isOverlap: Bool
    }

    enum MeetingTranscriptDocument {
        nonisolated static func markdown(
            startedAt: Date,
            endedAt: Date,
            turns: [MeetingTranscriptTurn],
            note: String? = nil
        ) -> String {
            var lines = [
                "# Meeting · \(displayTimestamp(startedAt))",
                "",
                "Started: \(displayTimestamp(startedAt))",
                "Ended: \(displayTimestamp(endedAt))",
                "Duration: \(formatDuration(endedAt.timeIntervalSince(startedAt)))",
                "",
            ]
            if let note, !note.isEmpty {
                lines.append(note)
                lines.append("")
            }
            if turns.isEmpty {
                lines.append("No speech was recognized in this recording.")
                lines.append("")
            } else {
                for turn in turns {
                    let overlap = turn.isOverlap ? " · overlapping" : ""
                    lines.append(
                        "**\(turn.speakerLabel)** (\(formatClock(turn.startSeconds))–\(formatClock(turn.endSeconds))\(overlap))"
                    )
                    lines.append("")
                    lines.append(turn.text.isEmpty ? "_No text_" : turn.text)
                    lines.append("")
                }
            }
            return lines.joined(separator: "\n")
        }

        nonisolated static func speakerLabel(
            identity: CapturedSpeakerIdentity,
            track: Int?
        ) -> String {
            switch identity {
            case .self:
                return "Me"
            case .known(_, let displayName):
                return displayName
            case .unresolved:
                return "Unresolved"
            case .other:
                if let track, track >= 0 {
                    return "Speaker \(track + 1)"
                }
                return "Speaker"
            }
        }

        nonisolated static func displayTimestamp(_ date: Date) -> String {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            return formatter.string(from: date)
        }

        nonisolated static func formatDuration(_ duration: TimeInterval) -> String {
            let total = max(Int(duration.rounded()), 0)
            let minutes = total / 60
            let seconds = total % 60
            if minutes == 0 {
                return "\(seconds)s"
            }
            return "\(minutes) min \(seconds)s"
        }

        nonisolated static func formatClock(_ seconds: Double) -> String {
            let total = max(Int(seconds.rounded()), 0)
            let minutes = total / 60
            let remainder = total % 60
            return String(format: "%d:%02d", minutes, remainder)
        }
    }
#endif
