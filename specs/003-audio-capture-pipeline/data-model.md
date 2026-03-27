# Data Model: Audio Capture Pipeline

## Overview

This feature is centered on a transient capture session that produces a temporary transcription-ready audio file and a live audio-level stream. It does not introduce durable user-owned persistence; the only file-backed artifact is the temporary recording output.

## Core Entities

### Capture Session

Represents one active recording lifecycle shared by dictation and microphone test consumers.

- `isActive`: whether capture is currently running
- `isPermissionGranted`: whether microphone permission was resolved successfully
- `selectedInputDevice`: the input device supplied by the audio device layer, if any
- `isWindowActivated`: whether the recording window has been activated
- `temporaryFileURL`: file URL for the in-progress or completed recording
- `didWriteAudio`: whether meaningful audio frames were written
- `writtenFrameCount`: total frame count written to the output file
- `duration`: optional final duration reported when capture stops

### Recording Outcome

Represents the result of stopping capture.

- `temporaryFileURL`: the file returned to the consumer
- `duration`: the final capture duration, if it can be measured
- `writtenFrameCount`: total number of frames written to the file
- `didWriteAudio`: whether the file contains meaningful audio
- `captureDiagnosticsSummary`: optional diagnostic text used for logging

### Audio Level Reading

Represents one normalized value emitted to the UI while capture is active.

- `level`: normalized floating-point value in the range `0...1`
- `minimumVisibleLevel`: the visible floor used when the capture is silent or the source is invalid

### Pending Audio Window

Represents the buffered audio held before the recording window is activated.

- `pendingBuffers`: FIFO buffer of audio frames
- `pendingFrameCount`: accumulated frame count in the pending window
- `maximumPendingSeconds`: 1.5 seconds of buffered audio

## Relationships

- A `Capture Session` produces at most one `Recording Outcome`.
- A `Capture Session` owns one temporary recording file per active recording attempt.
- A `Capture Session` emits many `Audio Level Reading` values during capture.
- A `Pending Audio Window` belongs to one `Capture Session` and is flushed when the recording window becomes active.

## State Transitions

1. `idle` -> `permission requested`
2. `permission resolved` -> `capturing`
3. `capturing` -> `window activated`
4. `capturing` -> `stopped`
5. `capturing` -> `canceled`
6. `stopped` -> `validated`
7. `validated` -> `discarded` when audio is insignificant

## Invariants

- Only one capture session is active at a time.
- A recording window must be activated before pending audio is written to the file.
- The pending audio window must not grow beyond the configured limit.
- Insignificant or empty recordings must not be treated as valid transcription input.
- The audio-level stream must remain safe to consume from multiple callers.

## Persistence

- The pipeline persists only the temporary recording file on disk while capture is active or until the consumer removes it.
- No durable feature-owned database record is created by this feature.
- Stable identifiers are external to the feature and come from upstream device selection; this feature only consumes the selected input device reference.
