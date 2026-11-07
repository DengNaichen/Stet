# Feature Specification: Fun-ASR Nano for macOS

**Feature Branch**: `codex/funasr-nano-macos`
**Created**: 2026-07-19
**Status**: Implemented
**Input**: Support `FunAudioLLM/Fun-ASR-Nano-2512` as a macOS-only local transcription engine.

## User Scenarios & Testing

### User Story 1 - Select Fun-ASR Nano (Priority: P1)

As a Mac user, I can select Fun-ASR Nano in Local Transcription settings and use it for dictation without sending audio to a remote service.

**Acceptance Scenarios**:

1. **Given** all Fun-ASR assets are installed, **When** Fun-ASR Nano is selected and dictation completes, **Then** Stet transcribes the captured audio with the local Fun-ASR runtime.
2. **Given** Fun-ASR Nano is selected but its assets are unavailable, **When** a dictation pipeline is created, **Then** Stet uses the existing local Whisper fallback.
3. **Given** Stet is built for a non-macOS platform, **When** StetEngine is resolved, **Then** the Fun-ASR binary runtime is not linked for that platform.

### User Story 2 - Install Model Assets (Priority: P1)

As a Mac user, I can download all model components from Settings and see when the model is ready.

**Acceptance Scenarios**:

1. **Given** one or more components are missing, **When** Download is selected, **Then** Stet downloads the encoder, Q4_K_M language model, and FSMN-VAD files into Application Support.
2. **Given** a component is already present, **When** installation runs again, **Then** that component is not downloaded again.
3. **Given** a download returns a non-success HTTP response, **When** installation fails, **Then** no invalid component is installed and Settings shows the error.

### User Story 3 - Reuse the Loaded Runtime (Priority: P2)

As a Mac user, repeated dictations should not reload the encoder and language model for every audio file.

**Acceptance Scenarios**:

1. **Given** prewarming loaded the selected model, **When** transcription starts, **Then** the same in-process runtime is reused.
2. **Given** no prewarmed runtime exists, **When** one transcription runs, **Then** a transient runtime is released afterward.
3. **Given** concurrent requests reach the runtime, **When** inference runs, **Then** native context access is serialized.

### User Story 4 - Use Personal Dictionary Hotwords (Priority: P1)

As a Mac user, my enabled personal dictionary entries should guide Fun-ASR Nano during recognition, before optional transcript cleanup runs.

**Acceptance Scenarios**:

1. **Given** personal dictionary entries are enabled, **When** Fun-ASR Nano transcribes audio, **Then** the entries are included in the model's official hotword prompt format.
2. **Given** the personal dictionary is empty or disabled, **When** Fun-ASR Nano transcribes audio, **Then** the original prompt remains unchanged.
3. **Given** the loaded runtime is reused, **When** two transcriptions use different dictionaries, **Then** each request uses its own hotword prompt without reloading the model.

## Requirements

- **FR-001**: The feature MUST be available only on macOS.
- **FR-002**: The runtime MUST execute in process and MUST NOT depend on Python or an external command-line executable.
- **FR-003**: The runtime MUST use the official FunASR GGUF encoder path with a Qwen3 0.6B GGUF decoder and FSMN-VAD.
- **FR-004**: Model files MUST be downloaded after installation rather than bundled in the application.
- **FR-005**: The shipped native artifact MUST support arm64 and x86_64 Macs.
- **FR-006**: The loaded native model state MUST have a single serialized owner.
- **FR-007**: Missing or invalid model assets MUST fail with actionable errors.
- **FR-008**: The settings UI MUST identify Nano's supported languages as Chinese, English, and Japanese.
- **FR-009**: The runtime MUST pass enabled personal dictionary entries into Fun-ASR Nano using the upstream hotword prompt contract.

## Success Criteria

- **SC-001**: The StetASR package compiles and links against the static Fun-ASR runtime on macOS.
- **SC-002**: Model-manager tests cover full installation, idempotent installation, and HTTP failure.
- **SC-003**: Service tests prove prewarmed reuse and transient cleanup.
- **SC-004**: A real GGUF smoke test produces non-empty text from the official FunASR sample audio.
- **SC-005**: Service tests prove personal dictionary prompts reach the native engine and empty dictionaries remain absent.

## Assumptions

- Fun-ASR Nano performs its own language recognition; Stet does not force a language token.
- Personal dictionary entries are supplied as recognition hotwords and remain available to the optional rewrite cleanup stage.
- The default decoder is `qwen3-0.6b-q4km.gguf` to keep the total download and memory footprint practical.
