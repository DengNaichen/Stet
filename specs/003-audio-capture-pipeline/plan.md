# Implementation Plan: Audio Capture Pipeline

**Branch**: `003-audio-capture-pipeline` | **Date**: 2026-03-27 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/003-audio-capture-pipeline/spec.md`

## Summary

This feature documents the current audio capture pipeline used by dictation and microphone testing. The implementation captures audio through a shared macOS service, streams normalized audio levels to consumers, writes temporary transcription-ready files, and handles capture-window activation, device fallback, and empty-recording rejection.

## Technical Context

**Language/Version**: Swift  
**Primary Dependencies**: AVFoundation, CoreAudio, CoreMedia, Foundation  
**Storage**: Temporary audio files on disk; no durable feature-owned database state  
**Testing**: Swift Testing  
**Target Platform**: macOS capture path, with shared service protocols consumed from the app  
**Project Type**: Desktop app feature infrastructure  
**Performance Goals**: Low-startup-latency live capture, real-time audio levels, bounded startup retries  
**Constraints**: Must remain aligned with permission flow, device availability, and transcribable audio format requirements  
**Scale/Scope**: Single-user local capture pipeline shared by dictation and microphone testing

## Constitution Check

All required documents are present for this feature scope:
- `spec.md` defines prioritized, independently testable user stories, requirements, edge cases, success criteria, and assumptions.
- `data-model.md` covers the capture session, recording outcome, audio levels, and pending audio window.
- `contracts/` documents only the public boundaries consumed across modules.
- No `tasks.md` is created for this stage.

No constitutional violations require justification in `Complexity Tracking`.

## Project Structure

### Documentation (this feature)

```text
specs/003-audio-capture-pipeline/
├── plan.md
├── spec.md
├── data-model.md
└── contracts/
    ├── AudioCaptureService.md
    └── AudioLevelSource.md
```

### Source Code (repository root)

```text
Stet/Core/Speech/
├── AudioCaptureService.swift
├── ConfigurableSpeechService.swift
└── MacAudioCaptureService.swift

Stet/Core/Audio/
├── Levels/
│   ├── AudioLevelBridge.swift
│   └── AudioLevelNormalizer.swift
├── Recording/
│   ├── LinearPCMConversion.swift
│   ├── MacRecordingFileSupport.swift
│   └── MacRecordingFileStabilizer.swift
└── Capture/
    ├── MacCaptureAudioCaptureError.swift
    ├── MacCaptureAudioDevicePlanner.swift
    ├── MacCaptureAudioFileRecorder.swift
    ├── MacCaptureAudioSampleBufferConverter.swift
    └── MacCaptureAudioSessionFactory.swift

Stet/Features/Dictation/
└── MicrophoneTest/
    ├── DefaultMicrophoneTestService.swift
    ├── MicrophoneTestService.swift
    ├── MicrophoneTestView.swift
    └── MicrophoneTestViewModel.swift

StetTests/Core/
├── Audio/
│   ├── Levels/
│   │   └── AudioLevelBridgeTests.swift
│   ├── Recording/
│   │   ├── LinearPCMConversionTests.swift
│   │   └── MacRecordingFileSupportTests.swift
│   └── Capture/
│       ├── CaptureErrorTests.swift
│       ├── MacCaptureAudioDevicePlannerTests.swift
│       ├── MacCaptureAudioFileRecorderTests.swift
│       └── MacCaptureAudioSampleBufferConverterTests.swift
└── Speech/
    └── ConfigurableSpeechServiceTests.swift
```

**Structure Decision**: This feature is documented as shared capture infrastructure. The concrete macOS implementation lives under `Stet/Core/Speech`, `Stet/Core/Audio/Capture`, `Stet/Core/Audio/Levels`, and `Stet/Core/Audio/Recording`, with shared consumer coverage in dictation and microphone test features.

## Implementation Observations

The current code is the source of truth when it conflicts with the older `.kiro` draft.

- The shared public capture boundary is `AudioCaptureService`, not the lower-level recorder classes.
- The shared public level boundary is `AudioLevelSource`.
- The macOS capture path requests permission, starts the capture service, activates the recording window, and then returns the recording file URL from the shared service.
- The macOS recorder uses bounded startup retries and a fallback candidate list, but those details remain implementation details rather than product requirements.
- `MacAudioFileRecordingSession` buffers up to 1.5 seconds of pending audio before activation and writes the buffered audio once activated.
- Recording output is validated after stop; insignificant recordings are discarded.
- The older `.kiro` draft describes hard startup-latency and meter-rate expectations; the current implementation tracks startup timing internally, but those values are not contractual product guarantees.
- The current macOS path is an input-only capture pipeline (`voiceProcessingEnabled` is false in the recording session); the earlier draft's broader voice-processing framing is not reflected in the code.
- `DefaultMicrophoneTestService` reuses the shared capture service and activation flow.
- `MicrophoneTestView` in onboarding is not yet a completed public contract; the current implementation still contains placeholder behavior, so this plan does not promise onboarding capture as a finished deliverable.
- There is dedicated lower-level test coverage for conversion, file support, device planning, recorder failure handling, and shared speech-service integration, but no dedicated end-to-end `MacAudioCaptureService` contract test suite.

## Complexity Tracking

No constitution exceptions were required for this feature.
