# Feature Specification: BYOK Remote Transcribe and Rewrite Provider Selection on Mac

**Feature Branch**: `005-transcribe-details`  
**Created**: 2026-03-23  
**Status**: Draft  
**Input**: User description: "Mac 端 BYOK dictation cleanup 支持独立选择 transcribe provider 和 rewrite provider；只定义 Mac 端行为，不写 backend 实现。"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Choose the Transcription Provider (Priority: P1)

As a BYOK user, I can choose whether transcription is handled by OpenAI or Groq.

**Why this priority**: The dictation flow cannot begin unless the Mac app knows which remote provider should perform transcription.

**Independent Test**: Change the transcription provider setting on Mac, start dictation, and verify the Mac client requires the matching API key and routes the transcription request to the selected provider.

**Acceptance Scenarios**:

1. **Given** BYOK mode is enabled, **When** the user selects `OpenAI` as the transcription provider, **Then** the Mac app requires an OpenAI API key for transcription.
2. **Given** BYOK mode is enabled, **When** the user selects `Groq` as the transcription provider, **Then** the Mac app requires a Groq API key for transcription.
3. **Given** a transcription provider is selected and configured, **When** dictation starts, **Then** the Mac app sends the recorded audio to that selected provider for transcription.
4. **Given** the selected transcription provider is missing its API key, **When** the user tries to start dictation, **Then** the Mac app fails before any remote request is sent and explains which provider key is required for transcription.

---

### User Story 2 - Choose the Rewrite Provider Independently (Priority: P1)

As a BYOK user, I can choose whether rewrite is handled by OpenAI or Groq independently from the transcription provider.

**Why this priority**: Independent provider selection is the main missing capability. Without it, transcription and rewrite remain incorrectly coupled to one provider choice.

**Independent Test**: Set different providers for transcription and rewrite, verify the Mac app validates both required keys, then confirm transcription uses one provider and rewrite uses the other.

**Acceptance Scenarios**:

1. **Given** BYOK mode is enabled, **When** the user selects a rewrite provider, **Then** the Mac app stores that choice independently from the transcription provider.
2. **Given** transcription is set to `Groq` and rewrite is set to `OpenAI`, **When** dictation starts, **Then** the Mac app requires both a Groq API key and an OpenAI API key.
3. **Given** transcription is set to `OpenAI` and rewrite is set to `Groq`, **When** dictation starts, **Then** the Mac app requires both an OpenAI API key and a Groq API key.
4. **Given** the selected rewrite provider is missing its API key, **When** the user tries to start dictation, **Then** the Mac app fails before any remote request is sent and explains which provider key is required for rewrite.
5. **Given** transcription is set to `OpenAI` and rewrite is set to `Groq`, **When** the user views the current Mac BYOK settings, **Then** the app shows a configuration warning that this pair is not supported as a default BYOK pair on Mac.

---

### User Story 3 - Run Dictation as Two Remote Steps (Priority: P1)

As a BYOK user, I can rely on the Mac app to run dictation as a two-step remote flow: transcription first, rewrite second.

**Why this priority**: This is the product behavior that defines the feature. Provider selection only matters if the Mac app actually executes the two steps separately.

**Independent Test**: Start dictation in BYOK mode and verify the Mac client first obtains a transcript from the selected transcription provider, then sends that transcript to the selected rewrite provider, and finally returns rewritten text as the user-visible result.

**Acceptance Scenarios**:

1. **Given** valid recorded audio and all required API keys are configured, **When** dictation starts, **Then** the Mac app first sends the audio to the selected transcription provider.
2. **Given** transcription succeeds, **When** the Mac app receives transcript text, **Then** it keeps that transcript as an internal intermediate result and uses it as the input to the rewrite step.
3. **Given** rewrite succeeds, **When** the Mac app receives rewritten text, **Then** it returns that rewritten text as the final dictation result shown to the user.
4. **Given** transcription fails, **When** the first remote step returns an error, **Then** the Mac app stops the flow and does not attempt rewrite.
5. **Given** rewrite fails after transcription succeeds, **When** the second remote step returns an error, **Then** the Mac app reports a rewrite failure and does not pretend the overall dictation succeeded.

---

### User Story 4 - Get Clear Configuration Errors Before Dictation Starts (Priority: P2)

As a BYOK user, I get clear, user-directed configuration errors before dictation starts if the selected providers are not fully configured.

**Why this priority**: Provider flexibility increases configuration complexity. The Mac app must prevent wasted recording and failed requests by validating configuration up front.

**Independent Test**: Try all missing-key combinations and verify the Mac app blocks dictation before any network call and presents user-facing guidance that identifies the missing provider and step.

**Acceptance Scenarios**:

1. **Given** the transcription provider key is missing, **When** the user tries to start dictation, **Then** the Mac app blocks the flow before recording is processed and shows guidance for the missing transcription provider key.
2. **Given** the rewrite provider key is missing, **When** the user tries to start dictation, **Then** the Mac app blocks the flow before any remote request is sent and shows guidance for the missing rewrite provider key.
3. **Given** transcription and rewrite use different providers and both required keys are missing, **When** the user tries to start dictation, **Then** the Mac app reports that the selected setup requires two keys and identifies both missing providers.
4. **Given** the selected providers are fully configured, **When** the user starts dictation, **Then** the Mac app does not raise a configuration error and proceeds to the remote steps.

---

### Edge Cases

- What happens when the transcription provider and rewrite provider are different and only one of the two required API keys is configured?
- What happens when both required API keys are missing for a mixed-provider setup?
- What happens when the user selects `OpenAI` transcription with `Groq` rewrite, which the current Mac settings treat as an unsupported default pair?
- What happens when transcription succeeds but returns empty or whitespace-only text?
- What happens when rewrite is enabled but transcription fails before any rewrite request can be sent?
- What happens when the rewrite provider returns invalid or empty output after a valid transcript was produced?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The Mac app MUST support a dedicated `transcriptionProvider` setting in BYOK mode.
- **FR-002**: The Mac app MUST support a dedicated `rewriteProvider` setting in BYOK mode.
- **FR-003**: The Mac app MUST allow `transcriptionProvider` and `rewriteProvider` to be selected independently from `OpenAI` and `Groq`.
- **FR-004**: The Mac app MUST show a configuration warning when the current provider pair is `OpenAI` transcription with `Groq` rewrite, because the current Mac settings treat that pair as unsupported as a default BYOK pair.
- **FR-005**: The Mac app MUST run BYOK dictation as two distinct remote steps: transcription first, rewrite second.
- **FR-006**: The Mac app MUST send recorded audio to the selected transcription provider.
- **FR-007**: The Mac app MUST treat the transcript returned from transcription as an internal intermediate result and MUST NOT surface it as the final user-visible output of this flow.
- **FR-008**: The Mac app MUST send the intermediate transcript to the selected rewrite provider for dictation cleanup.
- **FR-009**: The Mac app MUST return the rewrite result as the final user-visible output of the BYOK dictation flow.
- **FR-010**: The Mac app MUST require the API key for the selected transcription provider before starting BYOK dictation.
- **FR-011**: The Mac app MUST require the API key for the selected rewrite provider before starting BYOK dictation.
- **FR-012**: If transcription and rewrite use different providers, the Mac app MUST require both providers' API keys before starting BYOK dictation.
- **FR-013**: The Mac app MUST validate all required provider keys before sending any remote request for the BYOK dictation flow.
- **FR-014**: If required keys are missing, the Mac app MUST fail before transcription begins.
- **FR-015**: Configuration errors MUST identify which step is blocked (`transcription` or `rewrite`) and which provider key is required.
- **FR-016**: Configuration errors SHOULD use user-directed guidance such as `Add an OpenAI API key to use OpenAI for rewrite.`
- **FR-017**: If transcription fails, the Mac app MUST stop the flow and MUST NOT attempt rewrite.
- **FR-018**: If rewrite fails, the Mac app MUST report rewrite failure and MUST NOT present a successful dictation result.
- **FR-019**: This feature spec MUST remain limited to Mac-side behavior and MUST NOT define backend implementation details.
- **FR-020**: This feature spec MUST remain limited to BYOK dictation cleanup and MUST NOT define managed/relay behavior.
- **FR-021**: This feature spec MUST NOT include selection rewrite.

### Key Entities *(include if feature involves data)*

- **Transcription Provider Selection**: The Mac-side BYOK setting that determines whether remote transcription uses OpenAI or Groq.
- **Rewrite Provider Selection**: The Mac-side BYOK setting that determines whether remote rewrite uses OpenAI or Groq independently from transcription.
- **Transcribe Request**: The Mac-side request that sends recorded audio to the selected transcription provider.
- **Intermediate Transcript**: The transcript text returned from the transcription provider and held by the Mac app as an internal result before rewrite.
- **Rewrite Request**: The Mac-side request that sends the intermediate transcript to the selected rewrite provider for cleanup.
- **Provider Configuration Validation**: The Mac-side preflight check that ensures all provider API keys required by the selected two-step BYOK flow are available before any remote request is started.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Mac-side automated tests cover successful BYOK dictation for the currently exercised provider combinations: `OpenAI -> OpenAI`, `Groq -> Groq`, and `Groq -> OpenAI`.
- **SC-002**: Mac-side automated tests cover mixed-provider route resolution, including the `OpenAI -> Groq` combination, without reintroducing execution-time route rejection.
- **SC-003**: Mac-side automated tests cover preflight configuration failures for missing transcription keys, missing rewrite keys, and mixed-provider setups missing both required keys.
- **SC-004**: Mac-side automated tests verify that transcription failure prevents rewrite from running.
- **SC-005**: Mac-side automated tests verify that rewrite failure is surfaced as a failed dictation result after successful transcription.
- **SC-006**: The Mac settings surface warns when the current provider pair is `OpenAI` transcription with `Groq` rewrite.
- **SC-007**: A developer can read this spec and identify a clear boundary between Mac responsibilities and backend responsibilities.
- **SC-008**: Existing managed/relay behavior remains outside the scope of this spec and is not implicitly changed by this feature definition.

## Assumptions

- This specification is limited to the macOS direct BYOK dictation-cleanup flow.
- Managed relay behavior remains outside the scope of this feature even though it shares some runtime surfaces.
- Provider API keys are stored per provider and reused by whichever pipeline step selects that provider.
- The settings UI may warn about some provider pairs while the lower execution layers still model direct-mode configuration by step.
