# Feature Specification: Audio Post-Processing

**Feature Branch**: `004-audio-post-processing`  
**Created**: 2026-03-27  
**Status**: Draft  
**Input**: User description: "Audio post-processing for captured audio files before transcription"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Remove Empty Captures Early (Priority: P1)

As the dictation pipeline, I want captures with no qualifying speech to be discarded before transcription so that empty recordings do not consume downstream transcription work.

**Why this priority**: This is the main value of the feature. If the capture has no useful speech, transcription should stop immediately.

**Independent Test**: Process a silent or speechless WAV capture and verify that the result is marked discardable and does not continue as a transcription input.

**Acceptance Scenarios**:

1. **Given** a WAV capture with no qualifying speech, **When** it is post-processed, **Then** the result is marked for discard.
2. **Given** a capture whose speech content never reaches the minimum speech duration, **When** it is post-processed, **Then** it is treated as speechless.

---

### User Story 2 - Improve Speech When It Is Worth It (Priority: P2)

As the dictation pipeline, I want speech captures to be enhanced only when the improvement is meaningful so that transcription receives clearer audio without unnecessary rewriting.

**Why this priority**: Enhancing useful speech improves transcription quality, but only when the gain is large enough to matter.

**Independent Test**: Process a speech-containing WAV capture that benefits from enhancement and verify that the output is rewritten only when the decision says enhancement is worthwhile.

**Acceptance Scenarios**:

1. **Given** a speech capture with a meaningful gain opportunity, **When** it is post-processed, **Then** it is rewritten into a new WAV file.
2. **Given** a speech capture whose gain decision is below the enhancement threshold, **When** it is post-processed, **Then** the original file is preserved.

---

### User Story 3 - Fail Open on Unsupported or Unusable Audio (Priority: P3)

As the dictation pipeline, I want unsupported or unreadable audio to pass through unchanged so that post-processing does not block transcription.

**Why this priority**: Reliability matters more than forcing enhancement. The system should keep working even when post-processing cannot help.

**Independent Test**: Process a non-WAV file or a WAV file that cannot be loaded and verify that the original file is returned unchanged.

**Acceptance Scenarios**:

1. **Given** a non-WAV input file, **When** it is post-processed, **Then** the original file is returned unchanged.
2. **Given** a WAV file that cannot be loaded for analysis, **When** it is post-processed, **Then** the original file is returned unchanged.
3. **Given** a speech capture whose enhancement step fails, **When** it is post-processed, **Then** the original file is returned unchanged.

### Edge Cases

- A capture with silence plus short clicks that never form a qualifying speech segment is treated as speechless.
- A speech capture that rewrites to identical samples does not create a new file.
- A capture with missing duration metadata still produces a valid result.
- The post-processing step must not fail the whole dictation flow just because enhancement is unavailable.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST analyze each captured audio file before transcription and decide whether it contains qualifying speech.
- **FR-002**: The system MUST ignore speech segments shorter than 0.4 seconds when determining whether a capture contains qualifying speech.
- **FR-003**: The system MUST mark a capture as discardable when no qualifying speech is detected.
- **FR-004**: The system MUST preserve the original capture unchanged when the input is not a WAV file or when the file cannot be loaded for analysis.
- **FR-005**: The system MUST compute an enhancement decision for speech-containing captures and rewrite audio only when the gain is meaningful.
- **FR-006**: The system MUST preserve the capture duration and keep the output compatible with the transcription pipeline when it rewrites audio.
- **FR-007**: The system MUST retain cleanup information for any temporary files that should be removed after processing.
- **FR-008**: The system MUST fail open when enhancement cannot be completed so transcription can continue with the original capture.

### Key Entities *(include if feature involves data)*

- **AudioPostProcessingResult**: The outcome of post-processing, including the selected audio URL, optional duration, cleanup URLs, and discard flag.
- **AudioAnalysis**: The speech and audio-quality summary used to decide whether to discard, pass through, or rewrite a capture.
- **SpeechEnhancementPlan**: The derived enhancement decision, including target level, gain, limiter, and smoothing values.
- **SpeechEnhancementResult**: The output of the enhancement step, including the final URL and whether audio was actually rewritten.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A silent or speechless capture is rejected before transcription begins.
- **SC-002**: A speech capture that benefits from enhancement is rewritten only when the feature can improve it in a meaningful way.
- **SC-003**: A speech capture that does not need enhancement continues through the pipeline unchanged.
- **SC-004**: Unsupported or unreadable input never blocks the dictation flow; it falls back to the original file.
- **SC-005**: Rewritten captures remain usable by the transcription stage and preserve the original capture duration.

## Assumptions

- Captures are file-backed and processed after recording stops.
- WAV is the only format eligible for post-processing analysis and enhancement.
- Keeping transcription available is more important than forcing enhancement.
- Any temporary files created during post-processing are short-lived and may be deleted after the transcription pipeline finishes with them.
