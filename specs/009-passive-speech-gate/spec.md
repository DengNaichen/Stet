# Feature Specification: Unified Speech Capture and Contextual Passive Listening

**Feature Branch**: `009-passive-speech-gate`
**Created**: 2026-08-03
**Status**: Draft
**Input**: User description: "Unify speech capture with FunASR Nano as the Mac default and FunASR Realtime as the iPhone default. Keep Mac passive listening continuously available whenever the active hotkey is not held. In passive mode, retain a bounded amount of detected speech temporarily so that another person's opening words can be recovered if the enrolled user subsequently participates. Transcribe the resulting relevant conversation, continue recognizing self versus other speakers throughout it, and discard surrounding conversations in which the user never participates. While the hotkey is held, disable passive processing and send all captured audio through active transcription regardless of speaker identity."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - All-day passive transcription on Mac (Priority: P1)

As a Mac user, passive listening remains available whenever active capture is not in progress. When another person speaks first, their opening words remain available briefly instead of being discarded immediately. If I participate soon afterward, the system treats the exchange as relevant, includes the retained opening words, and continues capturing both sides of the conversation. Surrounding conversations in which I do not participate expire without transcription. Within every accepted transcript, the system distinguishes my speech, explicitly enrolled known speakers, and unknown or unresolved speech.

**Why this priority**: The core value is capturing conversations involving the user without continuously transcribing unrelated office speech.

**Independent Test**: Leave the application in passive mode and test silence, unrelated other-speaker conversations, conversations where another person speaks before the enrolled user replies, and conversations initiated by the enrolled user. Verify that unrelated speech expires without transcription, relevant conversations include eligible leading context, and accepted transcripts label distinguishable speech as self or other.

**Acceptance Scenarios**:

1. **Given** the Mac application is running with microphone permission and the active hotkey is not held, **When** no one is speaking, **Then** passive listening remains available without invoking speaker verification or transcription.
2. **Given** passive listening is available, **When** another person speaks first, **Then** the detected speech is held only in a bounded transient pending buffer and is not yet transcribed or persisted as an entry.
3. **Given** another person's opening speech is still pending, **When** the enrolled user participates before the relevance deadline, **Then** a relevant conversation opens and transcription includes the eligible pending opening speech, the user's response, and subsequent turns.
4. **Given** pending speech contains no enrolled-user participation before the relevance deadline, **When** the deadline expires, **Then** the pending audio is discarded without transcription or a transcript entry.
5. **Given** the enrolled user initiates speech while passive listening is available, **When** the user's voice is verified, **Then** a relevant conversation opens immediately and produces a faithful transcript without losing opening words or rewriting the result.
6. **Given** a relevant conversation is open, **When** another person continues speaking without the user appearing in every individual speech segment, **Then** those turns remain part of the relevant conversation until its relevance deadline expires.
7. **Given** an accepted passive conversation contains the enrolled user, an explicitly enrolled known speaker, and an unknown speaker, **When** transcription completes, **Then** distinguishable speech regions are labeled as self, that known speaker, or other with confidence, while uncertain or overlapping regions remain explicitly unresolved.
8. **Given** passive listening is enabled, **When** the user turns its independent setting off, **Then** passive capture stops without disabling hotkey-controlled active dictation; the setting persists and turning it back on restores passive listening when its prerequisites are available.

---

### User Story 2 - Hotkey-controlled active transcription (Priority: P2)

As a user, I can hold the transcription hotkey to enter active mode. During that interval, all captured speech is processed as an intentional output regardless of who spoke, without passive speaker verification deciding whether the content is accepted.

**Why this priority**: Active dictation must remain predictable and must take precedence over passive classification.

**Independent Test**: While passive listening is available, hold the hotkey and play speech from the user and another speaker; verify that the complete hotkey interval is handled as active transcription and neither voice is rejected by passive speaker logic.

**Acceptance Scenarios**:

1. **Given** no hotkey is pressed, **When** speech occurs, **Then** it follows the passive speech-detection and enrolled-user verification flow.
2. **Given** the hotkey is held, **When** any speaker talks, **Then** the entire captured interval is submitted to active transcription without application-level speech gating or speaker-based rejection.
3. **Given** the user presses the hotkey while passive listening is evaluating speech, **When** active capture begins, **Then** passive processing is suspended for the complete active interval and that interval cannot also produce a passive entry.
4. **Given** active capture is in progress, **When** the hotkey is released, **Then** the transcript is finalized using the selected engine's own speech-boundary behavior and the system returns immediately to passive mode.

---

### User Story 3 - Consistent engine behavior across Mac and iPhone (Priority: P3)

As a user of both Stet applications, I encounter the same active-capture semantics while each device uses the engine suited to its role: FunASR Nano by default on Mac and FunASR Realtime by default on iPhone.

**Why this priority**: Consistent behavior reduces maintenance and user confusion while preserving the intended local Mac and cloud iPhone deployment choices.

**Independent Test**: Reset engine preferences on both platforms, complete an active transcription on each, and verify the expected default engine and equivalent capture lifecycle behavior.

**Acceptance Scenarios**:

1. **Given** a new or reset Mac installation, **When** transcription is first used, **Then** FunASR Nano is selected by default.
2. **Given** a new or reset iPhone installation, **When** transcription is first used, **Then** FunASR Realtime is selected by default.
3. **Given** the user performs active capture on either platform, **When** the capture ends, **Then** each platform relies on its selected engine's speech-boundary handling rather than applying an additional precise trimming pass.
4. **Given** the available engine list is displayed, **When** the user reviews the supported choices, **Then** SenseVoice is not offered as a transcription engine.

### Edge Cases

- A brief non-speech sound, steady room noise, or silence must not create an empty transcript entry.
- Speech that starts suddenly must retain enough preceding audio to avoid clipping its first word.
- A short pause inside an utterance or normal turn-taking must not unnecessarily end a relevant conversation; sustained inactivity must eventually close it.
- A long uninterrupted utterance must be divided into bounded, processable entries without losing audio at the boundary.
- Pressing the active hotkey while passive context is pending must suspend passive relevance evaluation; active speech must not retroactively qualify pending context as a relevant passive conversation or create duplicate entries.
- Other people speaking nearby, including sustained office conversation, must remain untranscribed and expire when the enrolled user's voice never appears within the pending relevance window.
- If another person speaks longer than the bounded pending buffer before the user joins, the oldest audio may expire; the retained portion must remain ordered and unclipped at its internal boundaries.
- If the user speaks shortly after an unrelated nearby conversation, temporal proximity may admit unrelated leading speech; the system must preserve speaker labels and apply a bounded lookback rather than claiming semantic certainty.
- If simultaneous speech includes the enrolled user's voice, the candidate may be transcribed as one faithful interval; distinguishable regions are still labeled, while the overlapping region is left unresolved for later agent processing rather than source-separated.
- Music, television, or a recorded non-user voice containing speech must expire without transcription when the enrolled user's voice is absent during the pending window.
- If the user listens silently and never speaks, the passive system cannot reliably distinguish a relevant conversation from unrelated office speech and is not required to retain it.
- If speech detection, speaker verification, or transcription fails, passive mode must remain available for later utterances without fabricating content.
- Loss of microphone permission, input-device disconnection, or loss of network access for the iPhone cloud engine must be surfaced without silently continuing capture.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: On Mac, passive listening MUST be enabled by default and, while enabled, MUST be the default state whenever the application is running with microphone permission and active capture is not in progress.
- **FR-002**: The system MUST visibly indicate when passive listening or active capture is using the microphone.
- **FR-003**: During Mac passive listening, the system MUST continuously perform only low-cost speech-presence detection until candidate speech is found.
- **FR-004**: Detected passive speech MUST enter a bounded transient pending-context buffer rather than being immediately transcribed, persisted, or discarded.
- **FR-005**: The pending-context buffer MUST retain sufficient audio around speech and across recent speaker turns to recover eligible opening context without clipping words.
- **FR-006**: Periods containing no detected speech MUST NOT invoke speaker verification or transcription and MUST NOT create transcript entries.
- **FR-007**: Speaker verification MUST run only on detected passive speech and MUST NOT continuously process silence.
- **FR-008**: Detecting the enrolled user's voice in pending speech before the relevance deadline MUST open a relevant conversation.
- **FR-009**: Opening a relevant conversation MUST admit the eligible pending context that preceded the user's detected participation, preserving its original order and speaker timing.
- **FR-010**: While a relevant conversation remains open, subsequent detected speech from any speaker MUST remain eligible for transcription without requiring the enrolled user to appear in every individual speech segment.
- **FR-011**: Pending speech in which the enrolled user's voice is not detected before the relevance deadline MUST be discarded without transcription or a transcript entry.
- **FR-012**: A relevant conversation MUST close after a bounded period of inactivity or absence of further enrolled-user participation; later speech MUST return to pending evaluation.
- **FR-013**: Accepted conversation audio MUST invoke transcription, and within each bounded speaker-turn work item the selected transcription engine MUST remain responsible for final speech segmentation.
- **FR-014**: Speaker recognition MUST cover the full accepted conversation and MUST label each distinguishable speech region as the enrolled user, an explicitly enrolled known speaker, or another speaker with confidence.
- **FR-015**: Speaker regions that cannot be reliably classified, including overlapping speech, MUST remain explicitly unresolved rather than receiving a fabricated identity label.
- **FR-016**: While the active hotkey is held, the system MUST disable passive processing, MUST submit the complete captured interval for transcription regardless of speaker identity, and MUST NOT use active speech to open or maintain a passive relevant conversation.
- **FR-017**: Active and passive flows MUST prevent the same captured interval from producing duplicate transcript entries.
- **FR-018**: Releasing the active hotkey MUST finalize active capture using the selected engine's own speech-boundary behavior.
- **FR-019**: Passive mode MUST resume automatically as soon as the active hotkey interval finishes.
- **FR-020**: FunASR Nano MUST be the default transcription engine for new or reset Mac installations.
- **FR-021**: FunASR Realtime MUST be the default transcription engine for new or reset iPhone installations.
- **FR-022**: An existing explicit engine choice MUST be preserved during upgrade when that engine remains supported.
- **FR-023**: SenseVoice MUST no longer appear as a supported transcription engine or as a default choice.
- **FR-024**: The active hotkey capture lifecycle MUST have equivalent user-visible semantics across Mac and iPhone, even when their selected engines perform segmentation differently.
- **FR-025**: Pending raw audio MUST be held only in bounded transient storage; expired pending audio MUST be discarded, and accepted raw audio MUST be discarded after required transcription and speaker recognition complete, unless the user explicitly chooses a separate recording feature.
- **FR-026**: Transcripts, conversation-window decisions, speaker-region labels, and failure states MUST remain associated with their capture time and mode when an entry is created.
- **FR-027**: A failure while evaluating pending context or processing an accepted conversation MUST NOT terminate passive listening.
- **FR-028**: The user MUST be able to keep one owner voice profile and MAY enroll named profiles for people whose consented reference speech is available; unknown speakers MUST remain open-set `other` rather than being forced to the closest enrolled profile.
- **FR-029**: Deleting an enrolled speaker profile MUST remove its retained reference voice data, and future regions for that person MUST be treated as unknown unless the profile is enrolled again.
- **FR-030**: The user MUST be able to enable or disable passive listening independently of active dictation; disabling it MUST stop and clear passive capture without interrupting an active capture, and the preference MUST persist across launches.

### Scope Boundaries

- This feature provides transcription, enrolled-user admission verification, and enrolled/other/unresolved speaker labeling within accepted passive entries; it does not rewrite, summarize, or semantically edit transcript text.
- Passive all-day listening is a Mac feature in this scope. The iPhone cloud engine is not required to provide all-day passive listening.
- Passive relevance is inferred from the enrolled user's participation within a bounded temporal window, not from semantic understanding of what nearby speakers are discussing.
- Initial passive speaker verification opens a relevant conversation. After admission, speaker recognition remains part of the transcription flow so that the accepted entry can distinguish self from other speakers.
- Identifying explicitly enrolled, consented known speakers is in scope; discovering or naming arbitrary unknown third parties is out of scope.
- Separating simultaneous speakers into independent audio streams is out of scope. An accepted candidate remains one transcript with distinguishable regions labeled and overlapping regions available for later agent processing.
- Inferring that speech is addressed to a silently listening user is out of scope because voice activity and speaker identity alone cannot distinguish it from unrelated office speech.
- This feature does not persist continuous raw audio or provide a general-purpose audio recorder; it uses only a bounded transient lookback buffer.

### Key Entities

- **Listening State**: The current mutually exclusive Mac capture state: unavailable, passive armed, passive pending, passive relevant conversation, or hotkey-controlled active capture.
- **Capture Interval**: A bounded span of microphone audio associated with passive or active mode and a capture timestamp.
- **Pending Context Buffer**: A bounded, transient, ordered collection of recent detected speech awaiting evidence that the enrolled user is participating.
- **Relevant Conversation**: A passive interval opened by detecting the enrolled user's voice; includes eligible leading pending context and subsequent speaker turns until its relevance deadline expires.
- **Transcript Entry**: Faithful recognized text produced by active capture or an accepted relevant conversation, associated with its capture time, capture mode, ordered speaker regions, processing status, and any failure state.
- **Speaker Gate Decision**: The result used to open or maintain a relevant conversation; records whether the enrolled user's voice was detected together with confidence when available.
- **Speaker Profile**: A stable owner or named-known-speaker identity created from explicit reference speech; deleting it removes its retained reference voice data.
- **Speaker Region**: An ordered portion of an accepted passive interval associated with self, a known speaker profile, other, or unresolved status and confidence when available.
- **Engine Preference**: The user's selected transcription engine per platform, including whether the choice was explicit or inherited from the platform default.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In a 60-minute silent passive session, the system creates zero transcript entries and dispatches zero speaker-verification or transcription jobs.
- **SC-002**: Across a scripted set of at least 100 enrolled-user utterances with varied onset timing, at least 95% of transcripts retain the complete first and last spoken words.
- **SC-003**: In an other-speaker-only evaluation, 100% of pending audio is discarded within one second after its configured relevance deadline and none is persisted as a transcript entry.
- **SC-004**: In a controlled single-speaker evaluation, at least 90% of enrolled-user samples open a relevant conversation and at least 95% of other-speaker-only samples expire without transcription.
- **SC-005**: Across at least 50 scripted conversations in which another person speaks first and the enrolled user replies within the supported lookback window, at least 90% of resulting transcripts include the retained opening speech in the correct order.
- **SC-006**: On new or reset installations, 100% of Mac test installations select FunASR Nano and 100% of iPhone test installations select FunASR Realtime.
- **SC-007**: For identical active-capture test scenarios on Mac and iPhone, users can start, finish, and obtain a transcript using the same interaction sequence without configuring speech-boundary controls.
- **SC-008**: In a failure-recovery test, passive mode successfully processes the first valid enrolled-user utterance following a transcription, speaker-verification, or speaker-region-recognition failure without requiring an application restart.
- **SC-009**: In acceptance testing, 100% of generated transcript text matches the selected engine's returned text apart from documented formatting normalization; no rewriting stage changes wording or meaning.
- **SC-010**: In active-mode acceptance testing, 100% of completed hotkey intervals invoke transcription regardless of whether the enrolled user or another speaker supplied the audio.
- **SC-011**: In a controlled accepted-passive evaluation containing alternating self and other speech, at least 90% of distinguishable speech regions receive the correct self/other label, and 100% of regions below the confidence requirement remain unresolved rather than receiving a confident label.
- **SC-012**: In an eight-hour mixed passive-session test, other-speaker-only conversations produce no transcript entries, accepted relevant conversations contain at most one copy of each captured interval, and active-hotkey intervals produce no duplicate passive entry.
- **SC-013**: In a controlled evaluation of explicitly enrolled known speakers, at least 90% of their distinguishable speech regions receive the correct profile label, and unknown-speaker regions are never forced to a known profile below the confidence requirement.

## Assumptions

- The user enrolls enough reference speech before relying on passive enrolled-user filtering.
- Passive listening remains available while the Mac application is running and has microphone permission; quitting the application or revoking permission stops capture.
- Passive listening is intended for environments where the user has permission to capture speech; consent and recording-law compliance remain the user's responsibility and must be supported by clear microphone-state visibility.
- FunASR Nano can run locally on supported Macs, while FunASR Realtime requires network access on iPhone.
- Existing lightweight speech detection and the installed speaker-embedding runtime may be reused even though SenseVoice is removed as a selectable transcription model.
- Existing explicit engine preferences are preserved when still supported; defaults apply to new installations, reset preferences, and users whose previous engine is no longer available.
- Temporary buffering is permitted only as needed to preserve utterance boundaries, retain bounded leading context while relevance is unresolved, and complete in-flight processing.
- Speaker verification establishes voice similarity, not liveness; playback of the enrolled user's recorded voice may be accepted as the user's voice.
- Exact speech-gate thresholds, pending lookback duration, relevant-conversation timeout, maximum candidate length, and confidence calibration are implementation decisions to be defined and validated during technical planning.
