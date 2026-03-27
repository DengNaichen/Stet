# Data Model: Audio Post-Processing

## Overview

This feature models the outcome of post-processing a captured audio file, the analysis used to make that decision, and the enhancement plan/result used when speech should be rewritten.

## Core Entities

### `AudioPostProcessingResult`

Represents the final outcome of processing a captured audio file.

| Field | Meaning |
| --- | --- |
| `url` | The audio file that should move forward in the pipeline. |
| `duration` | The capture duration, when available. |
| `cleanupURLs` | Temporary files that may be deleted after the downstream pipeline finishes using the result. |
| `shouldDiscardAsNoSpeech` | Whether the capture should be treated as speechless and stopped before transcription. |

### `AudioAnalysis`

Represents the summary of the captured audio after local analysis.

| Field | Meaning |
| --- | --- |
| `shouldDiscardAsNoSpeech` | Whether the capture contains no qualifying speech. |
| `speechFrameRatio` | The share of analyzed time that is classified as speech. |
| `noiseFloorDBFS` | Estimated noise-floor level. |
| `speechLevelP75DBFS` | Estimated speech level at the 75th percentile. |
| `overallPeakDBFS` | Highest observed peak level. |
| `recommendedGainDB` | The gain recommended by the analysis stage. |

Derived relationship:
- `speechEnhancementPlan` is computed from the analysis result and is not stored independently.

### `SpeechEnhancementPlan`

Represents the enhancement decision derived from an analysis result.

| Field | Meaning |
| --- | --- |
| `shouldEnhance` | Whether the capture should be rewritten. |
| `targetSpeechLevelDBFS` | Desired target speech level. |
| `estimatedSpeechLevelDBFS` | Speech level estimated from analysis. |
| `estimatedNoiseFloorDBFS` | Noise floor estimated from analysis. |
| `appliedGainDB` | Gain chosen for enhancement. |
| `maxBoostDB` | Maximum allowed positive gain. |
| `maxCutDB` | Maximum allowed negative gain. |
| `limiterCeilingDBFS` | Ceiling used to prevent clipping. |
| `attackTime` | Gain ramp-up time. |
| `releaseTime` | Gain ramp-down time. |

### `SpeechEnhancementResult`

Represents the output of the enhancement step.

| Field | Meaning |
| --- | --- |
| `outputURL` | The file to use after enhancement. |
| `didRewriteAudio` | Whether a new file was actually written. |

## Relationships

- `AudioAnalysis` drives the decision to discard, pass through, or enhance.
- `SpeechEnhancementPlan` is derived from `AudioAnalysis`.
- `SpeechEnhancementResult` feeds into `AudioPostProcessingResult.rewritten`.
- `AudioPostProcessingResult` is the handoff object between the post-processing stage and the transcription stage.

## State Transitions

The feature has three observable processing outcomes:

1. **Passthrough**
   - Unsupported input, unreadable input, or enhancement that is not worthwhile stays as the original file.
2. **Discard**
   - Captures with no qualifying speech are marked as discardable.
3. **Rewritten**
   - Speech captures that benefit from enhancement are written to a new temporary WAV file.

These are not long-lived states. They are transient processing outcomes for a single capture.

## Persistence and Identity

- The feature does not persist domain data long term.
- The only persisted artifacts are transient audio files created during processing.
- File URLs are the stable identifiers for those transient artifacts within the scope of the pipeline run.
- `cleanupURLs` is the authoritative list of files that may be deleted after downstream consumers finish with them.

## Invariants

- A discard result always has `shouldDiscardAsNoSpeech = true`.
- A passthrough or rewritten result always has `shouldDiscardAsNoSpeech = false`.
- A rewritten result always points `url` at the rewritten file and includes both the source and rewritten files in `cleanupURLs`.
- If enhancement does not produce a different file, no rewritten result is created.
- No persistent user preference or database record is introduced by this feature.
