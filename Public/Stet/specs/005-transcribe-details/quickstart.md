# Quickstart: Transcribe Details

## Goal

Validate BYOK dictation provider splitting on macOS without regressing dictation cleanup behavior.

## Entry Points

- Settings persistence and provider selection:
  - `StetMac/Features/MacShell/Openai/MacOpenAISettingsViewModel.swift`
  - `StetMac/Features/MacShell/Openai/MacOpenAISettingsView.swift`
- Runtime routing and pipeline wiring:
  - `StetMac/Core/DictationPipeline/DictationExecutionRoute.swift`
  - `StetMac/Core/DictationPipeline/DictationPipelineFactory.swift`
  - `StetMac/Core/Speech/ConfigurableSpeechService.swift`
- User-facing failure mapping:
  - `StetMac/Features/Dictation/DictationFailure.swift`
  - `StetMac/Features/Dictation/DictationViewModel.swift`

## Supported Provider Combinations

- `OpenAI -> OpenAI`
- `Groq -> Groq`
- `Groq -> OpenAI`

Unsupported default pair:

- `OpenAI -> Groq`

## Validation Matrix

1. Settings: transcription provider and rewrite provider persist independently.
2. BYOK preflight: missing transcription key, missing rewrite key, and missing both keys fail before remote work starts.
3. Runtime: supported provider pairs still execute as a two-step flow where transcription feeds rewrite and only rewritten text is returned.


## Commands

Targeted feature suites:

```bash
xcodebuild test -project Stet.xcodeproj -scheme Stet -destination 'platform=macOS,arch=arm64' \
  -only-testing:StetTests/LogicPrimitiveTests \
  -only-testing:StetTests/ConfigurableSpeechServiceTests \
  -only-testing:StetTests/DictationViewModelTests \
  -only-testing:StetTests/MacOpenAISettingsViewModelTests \
  -only-testing:StetTests/MacAppBootstrapperTests
```

Known-stable focused retry for the two historically flaky selections:

```bash
xcodebuild test -project Stet.xcodeproj -scheme Stet -destination 'platform=macOS,arch=arm64' \
  -only-testing:StetTests/ConfigurableSpeechServiceTests/byokUsesAIAudiencePromptWhenTargetAppIsUnknown
```

## Observed Outcomes

- `2026-03-23`: targeted validation passed with:

```bash
xcodebuild test -project Stet.xcodeproj -scheme Stet -destination 'platform=macOS,arch=arm64' \
  -only-testing:StetTests/LogicPrimitiveTests/dictationExecutionRouteResolverRejectsByokWithoutRequiredProviderKeys \
  -only-testing:StetTests/LogicPrimitiveTests/dictationExecutionRouteResolverRejectsByokWhenOnlyTranscriptionKeyIsMissing \
  -only-testing:StetTests/LogicPrimitiveTests/dictationExecutionRouteResolverRejectsByokWhenOnlyRewriteKeyIsMissing \
  -only-testing:StetTests/ConfigurableSpeechServiceTests/byokOpenAIToOpenAIReturnsOnlyRewrittenText \
  -only-testing:StetTests/ConfigurableSpeechServiceTests/byokGroqToGroqUsesSingleProviderForBothRemoteSteps \
  -only-testing:StetTests/ConfigurableSpeechServiceTests/byokGroqToOpenAIUsesIntermediateTranscriptOnlyForRewrite \
  -only-testing:StetTests/ConfigurableSpeechServiceTests/transcriptionFailurePreventsRewriteStepFromStarting \
  -only-testing:StetTests/ConfigurableSpeechServiceTests/rewriteFailureThrows \

  -only-testing:StetTests/DictationViewModelTests/stopFailurePreservesStepAwareProviderConfigurationFailure \
  -only-testing:StetTests/DictationViewModelTests/stopFailurePreservesUnsupportedProviderPairFailure \
  -only-testing:StetTests/MacDictationPanelViewModelTests/configurationFailuresAreSurfacedThroughPanelStatus \
  -only-testing:StetTests/ConfigurableSpeechServiceTests/byokUsesAIAudiencePromptWhenTargetAppIsUnknown
```

- Result: `** TEST SUCCEEDED **`
- The broader aggregate suite selection in this workspace can still duplicate some suites and intermittently misreport a few existing time-sensitive tests. The focused command above is the stable validation path used for this feature.
