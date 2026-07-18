# Implementation Plan: BYOK Remote Transcribe and Rewrite Provider Selection on Mac

**Branch**: `005-transcribe-details` | **Date**: 2026-03-27 | **Spec**: [spec.md](./spec.md)  
**Input**: Existing feature behavior implemented in the current codebase, documented without code changes

## Summary

This plan documents the current design of Stet's macOS BYOK provider-selection flow for dictation cleanup. The current implementation splits the direct path into two remote steps:

1. transcribe recorded audio with the selected transcription provider
2. rewrite the transcript with the selected rewrite provider

The goal of this document is not to propose a new refactor. It is to explain how the feature is structured today so that `spec.md` and `data-model.md` stay aligned with the current implementation.

## Technical Context

**Language/Version**: Swift with Swift Concurrency on macOS  
**Primary Dependencies**:
- Foundation and URLSession for remote requests
- SwiftUI for macOS settings UI
- UserDefaults for provider selection persistence
- Keychain-backed secret storage for provider API keys
- Existing OpenAI-compatible provider integrations for OpenAI and Groq

**Storage**:
- `UserDefaults` for `transcriptionProvider`, `rewriteProvider`, and execution-mode settings
- Keychain-backed secret storage for provider API keys
- In-memory snapshot and pipeline state at runtime

**Testing**:
- Swift Testing coverage in `StetTests/Core/DictationPipeline`
- Swift Testing coverage in `StetTests/Core/Speech`
- Swift Testing coverage in `StetTests/Features/MacShell/Openai`
- Feature-level failure-path coverage in `StetTests/Features/Dictation`

**Target Platform**: macOS  
**Project Type**: Native desktop application  
**Constraints**:
- Documentation must reflect the current implementation exactly
- No code changes are part of this pass
- No code changes are part of this pass
- `contracts/` stays empty unless there is a real external interface to document

## Constitution Check

This feature's documentation follows the current Constitution structure:

- `spec.md` is product-facing and limited to current Mac-side behavior.
- `data-model.md` is limited to domain entities, relationships, and invariants.
- `contracts/` remains empty because this feature does not currently expose a clean public interface across a module boundary that deserves separate contract documentation.
- `plan.md` is used as the feature's design document rather than as a task list.
- `tasks.md`, `research.md`, and `quickstart.md` may exist as supporting or older artifacts, but they are not the source of truth for this documentation pass.

## Project Structure

### Documentation

```text
specs/005-transcribe-details/
├── spec.md
├── plan.md
├── data-model.md
├── research.md
├── quickstart.md
├── contracts/
└── tasks.md
```

### Relevant Source Code

```text
StetMac/App/Lifecycle/
└── MacAppModel.swift

StetMac/Core/AIProviders/
├── OpenAI/
│   ├── OpenAIRewriteService.swift
│   └── OpenAITranscriptionService.swift
├── OpenAICompatible/
│   ├── OpenAICompatibleProviderConfiguration.swift
│   ├── OpenAIError.swift
│   └── OpenAISDKClientFactory.swift
└── Shared/
    └── DictationProviderPair.swift

StetMac/Core/DictationPipeline/
├── DictationExecutionRoute.swift
└── DictationPipelineFactory.swift

StetMac/Core/Speech/
└── ConfigurableSpeechService.swift

StetMac/Features/MacShell/Openai/
├── MacOpenAISettingsView.swift
└── MacOpenAISettingsViewModel.swift

StetMac/Shared/Utilities/
├── DictationSettingsStore.swift
└── MacPreferences.swift
```

### Relevant Tests

```text
StetTests/App/Lifecycle/
└── MacAppBootstrapperTests.swift

StetTests/Core/DictationPipeline/
└── DictationPipelineTests.swift

StetTests/Core/Speech/
└── ConfigurableSpeechServiceTests.swift

StetTests/Features/Dictation/
└── DictationViewModelTests.swift

StetTests/Features/MacShell/Openai/
└── MacOpenAISettingsViewModelTests.swift
```

## Design Overview

### 1. Settings Persistence And Snapshot Loading

`DictationSettingsStore` is the source of truth for the current direct-mode provider configuration. It:

- loads `transcriptionProvider`
- loads `rewriteProvider`, defaulting to the transcription provider when unset
- loads provider-scoped API keys from secure storage
- resolves those values into a `DictationSettingsSnapshot`

The current implementation stores API keys by provider, not by pipeline step.

### 2. Direct-Mode Preflight Validation

`DictationExecutionRouteResolver` validates direct-mode requirements before the recording flow reaches remote execution. It checks whether the selected transcription and rewrite providers each have a usable provider configuration and raises `ProviderConfigurationError.missingRequirements` when they do not.

The missing-requirements error is step-aware, so the UI can identify whether transcription, rewrite, or both are blocked.

### 3. Two-Step Direct Pipeline Assembly

`DictationPipelineFactory` builds a direct pipeline with:

- one transcription service configured from `TranscriptionProviderConfiguration`
- one optional rewrite service configured from `RewriteProviderConfiguration`

`ConfigurableSpeechService` then runs the flow in order:

1. build the pipeline
2. capture audio
3. transcribe audio
4. stop on transcription failure
5. rewrite the intermediate transcript when rewrite is enabled
6. return rewritten text as the final user-visible output

### 4. Settings UI Behavior

`MacOpenAISettingsViewModel` and `MacOpenAISettingsView` expose:

- execution-mode selection
- independent transcription-provider selection
- independent rewrite-provider selection
- only the credential fields needed for the currently selected providers
- a requirement message when selected providers are not fully configured

The current settings UI also shows a warning for the `OpenAI -> Groq` provider pair.

## Complexity Tracking

| Area | Why It Exists In The Current Design | Simpler Alternative Rejected By The Current Implementation |
|------|--------------------------------------|------------------------------------------------------------|
| Separate transcription and rewrite provider settings | The direct path allows independent provider selection for the two pipeline steps | One shared provider setting cannot represent mixed-provider flows |
| Provider-scoped key storage | OpenAI and Groq credentials are reused across whichever step selects that provider | Storing keys by step would duplicate secrets and complicate migration |
| Step-aware preflight validation | The UI needs to tell users exactly which step is blocked | A provider-only error would be harder to act on in mixed-provider setups |

## Implementation Observations

The items below are observations about the current implementation. They are not requests for code changes in this documentation pass.

### 1. This Feature Folder Predates The Current Constitution

`005-transcribe-details` already contained `research.md`, `quickstart.md`, and `tasks.md` from an older workflow. Those files may still be useful context, but in this pass the source of truth is the current `spec.md`, `plan.md`, and `data-model.md`.

### 2. Settings Warn About `OpenAI -> Groq`, But The Lower Layers Can Represent It

`MacOpenAISettingsViewModel` surfaces `OpenAI transcription with Groq rewrite is not supported as a default BYOK pair on Mac.` as a settings warning. The lower execution layers do not reject that pair generically; they validate configuration requirements and can still represent the mixed pair in direct-mode data structures.

### 3. `rewriteEnabled` Is Effectively Always On In The Current Settings Store

`DictationSettingsStore.loadRewriteEnabled()` currently returns `true`, even though there is still a `saveRewriteEnabled(_:)` path. For the current implementation, the practical product behavior is that BYOK dictation cleanup remains a two-step flow.

### 4. No Separate Public Contract Has Been Stabilized Yet

This feature currently relies on internal types such as `DictationSettingsStore`, `DictationExecutionRouteResolver`, and `DictationPipelineFactory`, but none of them currently form a stable external contract that needs to be documented under `contracts/`.
