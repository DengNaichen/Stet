import Foundation
import SwiftData

// MARK: - HistoryEntryStatus

public enum HistoryEntryStatus: String, Codable, Sendable {
    /// Capture started; raw/LLM text may be present but final delivery is pending.
    case processing
    /// Text was successfully injected into or copied to the target app.
    case completed
    /// Text is waiting in the clipboard for the user to manually paste (Enter not yet pressed).
    case clipboardPending
}

// MARK: - HistoryEntry

/// A single dictation session record capturing all three lifecycle stages:
/// raw ASR output → LLM-refined output → final delivered text.
@Model
public final class HistoryEntry {
    public var id: UUID
    public var timestamp: Date

    /// Raw transcript from the ASR engine (Whisper / SenseVoice / etc.).
    public var rawText: String

    /// LLM-refined text, if a rewrite transformer was active. Nil when rewrite is off.
    public var llmText: String?

    /// The text that was ultimately delivered to the target app.
    /// Nil until the delivery step completes.
    public var finalText: String?

    /// Bundle identifier of the frontmost app at the time dictation started,
    /// e.g. "com.tinyspeck.slackmacgap".
    public var targetBundleID: String?

    /// Localized display name of the target app, e.g. "Slack".
    public var targetAppName: String?

    public var status: HistoryEntryStatus

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        rawText: String,
        llmText: String? = nil,
        finalText: String? = nil,
        targetBundleID: String? = nil,
        targetAppName: String? = nil,
        status: HistoryEntryStatus = .processing
    ) {
        self.id = id
        self.timestamp = timestamp
        self.rawText = rawText
        self.llmText = llmText
        self.finalText = finalText
        self.targetBundleID = targetBundleID
        self.targetAppName = targetAppName
        self.status = status
    }
}

// MARK: - Codable export support

extension HistoryEntry {
    public struct ExportRepresentation: Codable, Sendable {
        public let id: UUID
        public let timestamp: Date
        public let rawText: String
        public let llmText: String?
        public let finalText: String?
        public let targetBundleID: String?
        public let targetAppName: String?
        public let status: String

        public init(from entry: HistoryEntry) {
            self.id = entry.id
            self.timestamp = entry.timestamp
            self.rawText = entry.rawText
            self.llmText = entry.llmText
            self.finalText = entry.finalText
            self.targetBundleID = entry.targetBundleID
            self.targetAppName = entry.targetAppName
            self.status = entry.status.rawValue
        }
    }
}
