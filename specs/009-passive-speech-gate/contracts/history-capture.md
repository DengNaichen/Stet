# Public Contract: Captured Transcript History

## Boundary

This is the new public `StetCore` boundary consumed by the Mac app when it persists an accepted passive conversation. It extends the existing history API without exposing microphone buffers, FluidAudio types, profile embeddings, or private inference services.

## Value types

```swift
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

public struct CapturedSpeakerRegion: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let startMilliseconds: Int
    public let endMilliseconds: Int
    public let speaker: CapturedSpeakerIdentity
    public let text: String
    public let identitySimilarity: Double?
    public let activityConfidence: Double?
    public let isOverlap: Bool
}

public extension HistoryEntry {
    var captureMode: CaptureMode { get }
    var captureStartedAt: Date { get }
    var captureEndedAt: Date? { get }
    var processingState: TranscriptProcessingState { get }
    var processingFailureCode: String? { get }
    var speakerRegions: [CapturedSpeakerRegion] { get }
}
```

`identitySimilarity` is cosine similarity and MUST NOT be presented as a probability. `activityConfidence` is diarizer speech probability and MUST NOT be used as identity evidence.

## Service methods

```swift
@MainActor
public final class DictationHistoryService {
    @discardableResult
    public func createPassiveCapture(
        id: UUID,
        startedAt: Date
    ) throws -> UUID

    public func updatePassiveCapture(
        id: UUID,
        rawText: String,
        speakerRegions: [CapturedSpeakerRegion]
    ) throws

    public func finishPassiveCapture(
        id: UUID,
        endedAt: Date,
        rawText: String,
        speakerRegions: [CapturedSpeakerRegion]
    ) throws

    public func failPassiveCapture(
        id: UUID,
        endedAt: Date,
        failureCode: String,
        retainedText: String,
        speakerRegions: [CapturedSpeakerRegion]
    ) throws
}
```

The method names and types define consumer-visible behavior; persistence scheduling remains internal to `StetCore`.

## Inputs and constraints

- `id` is generated once by the passive coordinator and is idempotent for creation. A repeated create with the same ID MUST return the existing ID rather than insert a duplicate.
- `startedAt <= endedAt` when `endedAt` exists.
- Region offsets are non-negative, ordered, and contained by the capture duration.
- Overlapping audio is represented by one `unresolved` region with `isOverlap = true`.
- `rawText` is the ordered join of non-empty region text after only documented whitespace/punctuation normalization; it is not rewritten.
- Update/finish/fail with an unknown ID fails and never creates an implicit entry.
- Passive records set `captureMode = passive`, `llmText = nil`, `finalText = nil`, target application fields nil, and delivery status `notDelivered`.

## Outputs

- Creation returns the stable history entry UUID.
- Mutation methods complete only after the requested change has been accepted for persistence.
- `fetchRecent` returns passive and active entries in the existing timestamp order. Passive entries expose their decoded regions through the public history model.
- History export includes the speaker label snapshots and scores but never profile centroid data, model files, or raw audio.

## Error behavior

```swift
public enum PassiveHistoryError: Error, Equatable, Sendable {
    case invalidInterval
    case invalidRegionOrder
    case regionOutsideCapture
    case invalidOverlapIdentity
    case entryNotFound
    case persistenceUnavailable
}
```

- Validation failures reject the entire mutation and preserve the previous record.
- Persistence failure is returned to the coordinator. The coordinator may mark the conversation failed in memory, but it MUST delete temporary audio and MUST NOT fabricate transcript text.
- An inference failure is represented by `failPassiveCapture`; it is not converted to a storage error.

## Usage example

```swift
let id = UUID()
_ = try history.createPassiveCapture(id: id, startedAt: startedAt)

try history.updatePassiveCapture(
    id: id,
    rawText: "上午好 我们看一下这个设计",
    speakerRegions: [openingTurn, ownerTurn]
)

try history.finishPassiveCapture(
    id: id,
    endedAt: endedAt,
    rawText: "上午好 我们看一下这个设计",
    speakerRegions: [openingTurn, ownerTurn]
)
```
