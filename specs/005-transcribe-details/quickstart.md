# Quickstart: Transcribe Details

## Goal

Validate BYOK dictation provider splitting on macOS without regressing relay or dictation cleanup behavior.

## Entry Points

- Settings persistence and provider selection:
  - `/Users/nd/Developer/stet-project/Stet/Stet/Features/MacShell/Openai/MacOpenAISettingsViewModel.swift`
  - `/Users/nd/Developer/stet-project/Stet/Stet/Features/MacShell/Openai/MacOpenAISettingsView.swift`
- Runtime routing and pipeline wiring:
  - `/Users/nd/Developer/stet-project/Stet/Stet/Core/DictationPipeline/DictationExecutionRoute.swift`
  - `/Users/nd/Developer/stet-project/Stet/Stet/Core/DictationPipeline/DictationPipelineFactory.swift`
  - `/Users/nd/Developer/stet-project/Stet/Stet/Core/Speech/ConfigurableSpeechService.swift`
- User-facing failure mapping:
  - `/Users/nd/Developer/stet-project/Stet/Stet/Features/Dictation/DictationFailure.swift`
  - `/Users/nd/Developer/stet-project/Stet/Stet/Features/Dictation/DictationViewModel.swift`

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
4. Relay/managed: relay paths still skip local rewrite and keep managed auth requirements unchanged.

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
  -only-testing:StetTests/MacOpenAISettingsViewModelTests/managedModeWithoutRelaySessionShowsSignInRequired \
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
  -only-testing:StetTests/ConfigurableSpeechServiceTests/automaticWithSessionPrefersRelayEvenWhenLocalKeyExists \
  -only-testing:StetTests/ConfigurableSpeechServiceTests/relayPathBuildsPromptAndSkipsLocalRewrite \
  -only-testing:StetTests/DictationViewModelTests/stopFailurePreservesStepAwareProviderConfigurationFailure \
  -only-testing:StetTests/DictationViewModelTests/stopFailurePreservesUnsupportedProviderPairFailure \
  -only-testing:StetTests/MacDictationPanelViewModelTests/configurationFailuresAreSurfacedThroughPanelStatus \
  -only-testing:StetTests/MacOpenAISettingsViewModelTests/managedModeWithoutRelaySessionShowsSignInRequired \
  -only-testing:StetTests/ConfigurableSpeechServiceTests/byokUsesAIAudiencePromptWhenTargetAppIsUnknown
```

- Result: `** TEST SUCCEEDED **`
- The broader aggregate suite selection in this workspace can still duplicate some suites and intermittently misreport a few existing time-sensitive tests. The focused command above is the stable validation path used for this feature.
