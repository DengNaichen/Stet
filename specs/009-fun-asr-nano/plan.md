# Implementation Plan: Fun-ASR Nano for macOS

**Branch**: `codex/funasr-nano-macos` | **Date**: 2026-07-19 | **Spec**: [`spec.md`](./spec.md)

## Summary

Add Fun-ASR Nano as a fourth local transcription choice on macOS. The integration uses a small C ABI derived from the official FunASR `llama.cpp` runtime, packages it as a static universal XCFramework, wraps it with a Swift actor, and downloads the three GGUF components from Hugging Face through the existing Settings flow.

## Technical Context

**Language/Version**: Swift 6, C++17
**Target Platform**: macOS 14+, arm64 and x86_64
**Native Runtime**: FunASR commit `9474bdbffc349e96a4c9807a42a62309f4f02dc4`; llama.cpp commit `8086439a4cea94c71a5dfb8fe4ad1546aebd640f`
**Acceleration**: CPU kernels plus Apple Accelerate; Metal intentionally disabled
**Storage**: `~/Library/Application Support/Stet/Models/Fun-ASR-Nano/`
**Networking**: `URLSession` downloads with HTTP status validation
**Testing**: Swift Testing with injected downloader and runtime seams; native smoke test with official GGUF assets

## Constitution Check

- The runtime is scoped to macOS and does not change iOS behavior.
- Models are downloaded rather than increasing the application bundle by about 1 GB.
- Native state is owned by a Swift actor and never crosses concurrent inference calls unsafely.
- The app links a static library, so hardened-runtime distribution does not require signing a helper executable.
- The existing local Whisper fallback remains the only fallback path when the selected engine is unavailable.

**Gate result**: PASS

## Project Structure

### Relevant Source Code

```text
Packages/StetEngine/
├── Sources/StetASR/FunASRNanoRecognizer.swift
└── Vendor/FunASRPackage/
    ├── Artifacts/FunASRRuntime.xcframework
    ├── RuntimeSource/
    ├── Licenses/
    └── build-xcframework.sh
StetMac/
├── Core/FunASR/
│   ├── FunASRNanoModelManager.swift
│   └── FunASRNanoTranscriptionService.swift
├── Core/DictationPipeline/DictationPipelineFactory.swift
└── Features/MacShell/AudioSetting/
```

### Relevant Tests

```text
StetMacTests/Core/FunASR/
├── FunASRNanoModelManagerTests.swift
└── FunASRNanoTranscriptionServiceTests.swift
StetMacTests/Features/MacShell/AudioSetting/MacAudioSettingsViewModelTests.swift
```

## Design Overview

The C++ layer keeps the SAN-M encoder, Qwen model, llama context, sampler, and tokenized prompt alive behind an opaque pointer. Each transcription still invokes FSMN-VAD and creates per-segment encoder compute buffers. The Swift actor is the sole owner of that pointer and serializes prepare, transcribe, and teardown operations.

`FunASRNanoModelManager` treats the encoder, decoder, and VAD files as one logical model. `FunASRNanoContextManager` retains one prepared engine for dictation prewarming. `FunASRNanoTranscriptionService` adapts the file-based native API to Stet's `AudioFileTranscriptionService` contract.

The dependency from `StetASR` to `FunASRRuntime` is conditional on macOS, which keeps the existing multi-platform StetEngine package resolvable on iOS.

## Complexity Tracking

| Area | Reason |
|------|--------|
| C ABI wrapper | Swift cannot directly own the upstream C++ model objects, and an external process would complicate signing and lifecycle management. |
| Three-file model manifest | Nano's official GGUF path separates its speech encoder, autoregressive language model, and VAD. |
| Static XCFramework | Stet distributes a native Mac app and needs reproducible linkage for both Mac architectures. |

## Implementation Observations

- Fun-ASR Nano is not Whisper-compatible and cannot reuse Stet's whisper.cpp or Sherpa ONNX runtime.
- The upstream Nano prompt supports automatic Chinese, English, and Japanese transcription; Stet's language hint and preferred-spelling prompt are intentionally ignored.
- CPU-only compilation avoids Metal runtime/JIT concerns. Accelerate remains enabled for matrix operations.
- The binary artifact contains code only. GGUF model licensing and download remain upstream concerns at installation time.
