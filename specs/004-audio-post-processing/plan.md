# Implementation Plan: Audio Post-Processing

**Branch**: `004-audio-post-processing` | **Date**: 2026-03-27 | **Spec**: [`spec.md`](./spec.md)
**Input**: Feature specification from `specs/004-audio-post-processing/spec.md`

## Summary

Audio post-processing is a file-based stage that runs after capture stops and before transcription begins. It analyzes the recorded WAV file, discards captures with no qualifying speech, rewrites speech captures only when the gain is worthwhile, and falls back to passthrough when the file is unsupported, unreadable, or the enhancement path fails.

## Technical Context

**Language/Version**: Swift  
**Primary Dependencies**: Foundation, AVFoundation, FluidAudio  
**Storage**: Temporary audio files only; no long-lived feature state  
**Testing**: Swift Testing unit tests  
**Target Platform**: macOS dictation pipeline  
**Project Type**: Desktop app feature module  
**Performance Goals**: Keep post-processing lightweight enough to stay behind capture-stop latency rather than dominate it  
**Constraints**: File-based processing only; WAV is the post-processing input format; enhancement must fail open  
**Scale/Scope**: Single-capture processing within the dictation pipeline

## Constitution Check

- `spec.md` is written as a product specification and stays focused on user-visible behavior.
- `data-model.md` describes the domain objects and their relationships without drifting into implementation classes.
- `plan.md` is the design document and does not replace the spec or task list.
- `tasks.md` is intentionally not created for this pass.
- `contracts/` is intentionally omitted because this feature does not expose a real public boundary API outside the internal pipeline.
- No Constitution violations require justification.

## Project Structure

### Documentation (this feature)

```text
specs/004-audio-post-processing/
├── spec.md
├── plan.md
└── data-model.md
```

### Source Code (repository root)

```text
Stet/Core/Audio/Processing/
├── AudioPostProcessing.swift
├── AudioSignalAnalyzer.swift
├── DefaultAudioPostProcessor.swift
├── SpeechAwareGainProcessor.swift
└── SpeechEnhancementTypes.swift

Stet/Core/Speech/
└── ConfigurableSpeechService.swift

StetTests/Core/Audio/Processing/
├── AudioPostProcessingTests.swift
├── AudioSignalAnalyzerTests.swift
├── DefaultAudioPostProcessorTests.swift
├── SpeechAwareGainProcessorTests.swift
└── SpeechEnhancementTypesTests.swift

StetTests/Core/Speech/
└── ConfigurableSpeechServiceTests.swift
```

**Structure Decision**: The feature is implemented as an internal processing stage between capture and transcription. The documentation lives under `specs/004-audio-post-processing/`, while the behavior is anchored by the audio-processing types in `Stet/Core/Audio/Processing/` and the speech pipeline integration in `Stet/Core/Speech/ConfigurableSpeechService.swift`.

## Design

### Component Responsibilities

- `DefaultAudioPostProcessor` orchestrates loading, analysis, discard decisions, enhancement, and fallback behavior.
- `AudioSignalAnalyzer` computes speech presence, level statistics, and enhancement guidance.
- `SpeechAwareGainProcessor` applies frame-based gain smoothing and writes a rewritten WAV file when enhancement is worthwhile.
- `ConfigurableSpeechService` consumes the post-processing result, cleans up temporary files, and stops the pipeline early when no qualifying speech is detected.

## Implementation Observations

- The current implementation is more conservative than the old `.kiro` narrative in one important way: any non-WAV, unreadable, or enhancement-failed capture always falls back to the original file instead of failing the pipeline.
- `DefaultAudioPostProcessor` accepts a `settingsStore` parameter but does not currently use it; performance tracing is read directly from `UserDefaults.standard`.
- Rewritten captures carry both the source and rewritten URLs in `cleanupURLs`, and cleanup is handled by the speech service after processing.
- The observed code and tests are the source of truth for this feature; if the old `.kiro` text conflicts with the implementation, the implementation wins and the mismatch is recorded here instead of forcing the docs to match the older draft.

## Complexity Tracking

None. The current implementation already matches the intended feature shape, so no Constitution exceptions are required.
