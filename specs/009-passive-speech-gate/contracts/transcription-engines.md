# Public Contract: Transcription Engine Selection

## Boundary

This contract describes the public `StetCore` engine values consumed by Mac onboarding, settings, and pipeline construction. It also defines how retired stored values are handled. The iPhone's `MobileDictationEngine` remains private to `StetMobile`; its user-visible default is described here for consistency, not exposed as a shared API.

## Public values

```swift
public enum StoredTranscriptionEngine: String, CaseIterable, Sendable {
    case fluidAudio
    case funASRNano
    case localWhisper

    public static let `default`: StoredTranscriptionEngine = .funASRNano
}

public enum TranscriptionEngine: Equatable, Sendable {
    case fluidAudio
    case funASRNano
    case localWhisper(languageHint: String?)
}
```

`sherpaOnnxSenseVoice` is removed from both enums and MUST NOT be returned by settings, onboarding, or pipeline construction.

## Selection and migration rules

- With no stored Mac value, return `.funASRNano`.
- Preserve an explicit stored value when it still decodes to `fluidAudio`, `funASRNano`, or `localWhisper`.
- Treat `sherpaOnnxSenseVoice` and any other unsupported raw value as retired. Replace it with `.funASRNano` and persist the replacement once so every later read is stable.
- A new/reset iPhone installation selects FunASR Realtime.
- A retired iPhone SenseVoice value migrates to FunASR Realtime and is persisted once.
- Model availability failure does not silently change the user's stored supported Mac choice. The existing pipeline may surface preparation failure or apply its documented runtime fallback, but preference migration is reserved for retired values.

## Outputs and errors

- `StoredTranscriptionEngine.default` is deterministic and requires no I/O.
- Preference readers return a supported enum value and write only when migrating a missing/reset/retired value according to product settings semantics.
- Pipeline creation reports model preparation failures through the existing transcription error path.
- iPhone Realtime configuration/network failures remain user-visible and do not fall back to a removed local engine.

## Usage examples

```swift
let engine = UserDefaultsModelStorage().transcriptionEngine
// New install: .funASRNano
```

```swift
let supported = StoredTranscriptionEngine.allCases
// [.fluidAudio, .funASRNano, .localWhisper]
```

## Compatibility note

Removing the public SenseVoice enum cases is an intentional source-breaking cleanup for consumers that referenced those cases. The monorepo must update all exhaustive switches in the same change. Persisted raw values remain data-compatible through the migration rule above.
