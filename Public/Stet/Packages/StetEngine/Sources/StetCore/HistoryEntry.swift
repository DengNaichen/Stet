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
    /// Transcript is stored in history and was intentionally not delivered to another app.
    case notDelivered
}

public enum CaptureMode: String, Codable, Sendable {
    case active
    case passive
}

public enum TranscriptProcessingState: String, Codable, Sendable {
    case processing
    case completed
    case failed
}

public enum CapturedSpeakerIdentity: Codable, Equatable, Sendable {
    case `self`
    case known(profileID: UUID, displayName: String)
    case other
    case unresolved
}

public struct CapturedSpeakerRegion: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let startMilliseconds: Int
    public let endMilliseconds: Int
    public let speaker: CapturedSpeakerIdentity
    public let text: String
    public let identitySimilarity: Double?
    public let activityConfidence: Double?
    public let isOverlap: Bool

    public init(
        id: UUID,
        startMilliseconds: Int,
        endMilliseconds: Int,
        speaker: CapturedSpeakerIdentity,
        text: String,
        identitySimilarity: Double?,
        activityConfidence: Double?,
        isOverlap: Bool
    ) {
        self.id = id
        self.startMilliseconds = startMilliseconds
        self.endMilliseconds = endMilliseconds
        self.speaker = speaker
        self.text = text
        self.identitySimilarity = identitySimilarity
        self.activityConfidence = activityConfidence
        self.isOverlap = isOverlap
    }
}

public enum PassiveHistoryError: Error, Equatable, Sendable {
    case invalidInterval
    case invalidRegionOrder
    case regionOutsideCapture
    case invalidOverlapIdentity
    case entryNotFound
    case persistenceUnavailable
}

// MARK: - HistoryEntry

/// A single dictation session record capturing all three lifecycle stages:
/// raw ASR output → LLM-refined output → final delivered text.
@Model
public final class HistoryEntry {
    public var id: UUID
    public var timestamp: Date

    /// Raw transcript from the selected ASR engine.
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

    var captureModeRawValue: String = CaptureMode.active.rawValue
    var captureStartedAtStorage: Date?
    public var captureEndedAt: Date?
    var processingStateRawValue: String = TranscriptProcessingState.completed.rawValue
    public var processingFailureCode: String?
    public var speakerRegionsData: Data = Data()

    public var captureMode: CaptureMode {
        CaptureMode(rawValue: captureModeRawValue) ?? .active
    }

    public var captureStartedAt: Date {
        captureStartedAtStorage ?? timestamp
    }

    public var processingState: TranscriptProcessingState {
        TranscriptProcessingState(rawValue: processingStateRawValue) ?? .completed
    }

    public var speakerRegions: [CapturedSpeakerRegion] {
        (try? JSONDecoder().decode([CapturedSpeakerRegion].self, from: speakerRegionsData)) ?? []
    }

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        rawText: String,
        llmText: String? = nil,
        finalText: String? = nil,
        targetBundleID: String? = nil,
        targetAppName: String? = nil,
        status: HistoryEntryStatus = .processing,
        captureMode: CaptureMode = .active,
        captureStartedAt: Date? = nil,
        captureEndedAt: Date? = nil,
        processingState: TranscriptProcessingState = .completed,
        processingFailureCode: String? = nil,
        speakerRegions: [CapturedSpeakerRegion] = []
    ) {
        self.id = id
        self.timestamp = timestamp
        self.rawText = rawText
        self.llmText = llmText
        self.finalText = finalText
        self.targetBundleID = targetBundleID
        self.targetAppName = targetAppName
        self.status = status
        self.captureModeRawValue = captureMode.rawValue
        self.captureStartedAtStorage = captureStartedAt
        self.captureEndedAt = captureEndedAt
        self.processingStateRawValue = processingState.rawValue
        self.processingFailureCode = processingFailureCode
        self.speakerRegionsData = (try? JSONEncoder().encode(speakerRegions)) ?? Data()
    }

    func updatePassiveFields(
        endedAt: Date?,
        processingState: TranscriptProcessingState,
        failureCode: String?,
        rawText: String,
        speakerRegions: [CapturedSpeakerRegion]
    ) throws {
        captureEndedAt = endedAt
        processingStateRawValue = processingState.rawValue
        processingFailureCode = failureCode
        self.rawText = rawText
        speakerRegionsData = try JSONEncoder().encode(speakerRegions)
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
        public let captureMode: String
        public let captureStartedAt: Date
        public let captureEndedAt: Date?
        public let processingState: String
        public let processingFailureCode: String?
        public let speakerRegions: [CapturedSpeakerRegion]

        public init(from entry: HistoryEntry) {
            self.id = entry.id
            self.timestamp = entry.timestamp
            self.rawText = entry.rawText
            self.llmText = entry.llmText
            self.finalText = entry.finalText
            self.targetBundleID = entry.targetBundleID
            self.targetAppName = entry.targetAppName
            self.status = entry.status.rawValue
            self.captureMode = entry.captureMode.rawValue
            self.captureStartedAt = entry.captureStartedAt
            self.captureEndedAt = entry.captureEndedAt
            self.processingState = entry.processingState.rawValue
            self.processingFailureCode = entry.processingFailureCode
            self.speakerRegions = entry.speakerRegions
        }
    }
}
