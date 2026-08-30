# Research: Unified Speech Capture and Contextual Passive Listening

## Decision 1: Mac is the passive host

**Decision**: Run all-day passive listening only on Mac. iPhone remains an intentional active-capture client.

**Rationale**: The user does not need this feature at the workstation to be portable, Mac has the sustained power and local model capacity, and the current specification explicitly scopes passive listening to Mac. iPhone already has a functioning Realtime websocket engine and stricter background/audio constraints.

**Rejected alternatives**:

- Phone as the all-day host: unnecessary portability and greater battery/background-policy cost.
- Mirrored passive capture on both devices: duplicate recordings and ownership conflicts without a product requirement.

## Decision 2: Application VAD wakes passive inference; engine VAD segments ASR

**Decision**: Use FluidAudio's streaming Silero VAD as the resident Mac speech gate. Do not run application-level precise trimming after a conversation is accepted. FunASR Nano and FunASR Realtime keep responsibility for their own final ASR endpointing.

**Rationale**: The current Mac `DefaultAudioPostProcessor` runs FluidAudio VAD only after an entire WAV exists, while Nano's C++ runtime runs VAD again. That cannot suppress all-day idle inference and duplicates segmentation. The pinned FluidAudio revision already exposes `VadManager.makeStreamState()` and `processStreamingChunk`; no new detector is needed.

**Rejected alternatives**:

- Trust Nano's internal VAD for passive wake-up: Nano would have to run continuously, defeating the energy gate.
- Apply both streaming VAD and precise batch trim: duplicates boundary decisions and can clip speech.
- One shared VAD implementation for Mac and iPhone: iPhone Realtime consumes live frames and server sentence boundaries; a forced abstraction would not remove meaningful code.

## Decision 3: Separate diarization from durable identity

**Decision**: Use FluidAudio Sortformer `.default` for accepted-conversation speaker tracks and the existing SherpaOnnx CAMPPlus speaker-embedding API for persistent owner/known-person identity.

**Rationale**: Sortformer is the pinned FluidAudio model with the strongest stable online tracks and pre-enrollment mapping, but enrollment survives only for one instance and must be rebuilt from original audio after launch. Persisting raw biometric recordings solely to warm Sortformer is unnecessary. Aggregate speaker embeddings are a few kilobytes, work with open-set thresholds, and match the Python validation already performed. The same embedding extractor can gate on owner participation and identify finalized Sortformer tracks.

FluidAudio still supplies the two capabilities it is best suited for here: low-cost streaming VAD and `who-spoke-when` diarization. Sherpa remains only for `who-this-voice-matches`.

**Rejected alternatives**:

- Speaker identification without diarization: cannot reliably preserve turns, overlaps, or another-first opening context in a multi-speaker accepted conversation.
- Sortformer enrollment as the durable identity database: no persistent embedding API; requires retained enrollment audio and has four ephemeral slots.
- FluidAudio legacy `DiarizerManager` for the whole live path: it has a durable 256-dimensional speaker database but is the heaviest online option, performs poorly on short/low-latency chunks, and requires external chunk alignment.
- LS-EEND: supports more speakers and overlap, but has more false alarms, less stable identity, and weaker enrollment. Revisit only if measured conversations routinely exceed Sortformer's four-track ceiling.
- Offline VBx: best full-file quality but cannot open a live relevance gate and would repeat accepted-audio processing.

## Decision 4: Open-set owner plus explicitly enrolled known profiles

**Decision**: Support exactly one owner and up to three explicitly enrolled known profiles in the first design. Unknown speech is never forced to the nearest profile.

**Rationale**: This covers “Me / User A / User B / Other” while matching Sortformer's four-track session ceiling. A threshold plus runner-up margin protects against false naming. A model revision or embedding-dimension mismatch requires re-enrollment.

**Rejected alternatives**:

- Unlimited profile enrollment: no current use case and implies UI, search, and calibration complexity beyond the four-track diarizer.
- Opportunistic profile learning from ambient audio: lacks consent and permits poisoning/misattribution.
- Closed-set nearest-neighbor assignment: always invents an identity for unknown people.

## Decision 5: Fifteen-second transient context with two close deadlines

**Decision**: Keep 15 seconds of 16 kHz mono Float32 in RAM, including 0.4 seconds of pre-roll. Probe owner identity with an initial 2-second window and 0.5-second hop once at least 1.2 seconds is voiced. End a relevant conversation after 10 seconds without speech or 60 seconds without another owner match. Seal individual processing work at VAD endpoints with a 30-second hard cap.

**Rationale**: Fifteen seconds costs about 0.96 MB and is long enough for a normal colleague opening before the user responds. The inactivity timeout keeps ordinary pauses together; the separate owner-absence timeout prevents other people from extending an admitted office conversation indefinitely. The hard cap bounds temporary files and local ASR work without splitting the logical history entry.

**Rejected alternatives**:

- Fixed-size transcription chunks only: cut words and conversation turns.
- One conversation timeout: either breaks normal turn-taking or captures unrelated follow-on speech forever.
- Persistent rolling files: violates the transient-pending-audio requirement and increases privacy exposure.

All timing and detection values remain grouped in one test-injectable internal configuration for real hardware calibration; they are not user settings.

## Decision 6: Transcribe finalized turns, not character-align one long string

**Decision**: Merge adjacent finalized diarization regions with the same identity and transcribe each ordered turn serially with the existing FunASR Nano file API. Treat simultaneous-speaker unions as one unresolved turn.

**Rationale**: `FunASRNanoRecognizer` currently returns only a `String`; the C++ runtime's internal VAD timestamps are not exposed and there are no word timestamps. A whole-conversation string cannot be honestly assigned to speaker regions by character count. Per-turn temporary WAVs produce a direct speaker/time/text association and require no runtime ABI change.

**Rejected alternatives**:

- Infer text ranges from audio duration or string length: fabricates alignment.
- Add timestamped Nano C/C++ output now: larger ABI/runtime change without proof that per-turn ASR is insufficient.
- Transcribe other-only pending speech before relevance: wastes compute and persists irrelevant content.

**Known ceiling**: Short turns may lose linguistic context and require more Nano invocations. Add timestamped whole-conversation ASR only if the evaluation corpus shows this approach misses the specification's accuracy target.

## Decision 7: Single capture owner and epoch-based hotkey preemption

**Decision**: Keep one normalized Mac capture stream and serialize mode changes in one actor. Split a crossing buffer at the hotkey sample boundary, seal an accepted passive conversation before that point, discard unaccepted pending context, and increment a capture epoch on every ownership change.

**Rationale**: The existing active recorder already owns the AVCapture stream and a 1.5-second pre-activation buffer. Extending the same owner avoids two microphone sessions. Epoch-tagged asynchronous work prevents late verification/ASR results from reopening or duplicating a newer mode.

**Rejected alternatives**:

- Independent active and passive recorders: device contention and unavoidable duplicate intervals.
- Let active speech qualify passive pending context: contradicts the user's mode semantics.
- Resume the old passive ring after hotkey release: leaks context across an intentional mode boundary.

## Decision 8: Extend existing history; store only centroid profiles

**Decision**: Extend `HistoryEntry` with capture/process metadata and a Codable speaker-region blob. Store aggregate speaker profiles in a local-only non-synchronizing Keychain item. Do not persist enrollment clips, pending audio, or per-clip embeddings.

**Rationale**: History is already the product's transcript store, and speaker regions are always loaded with their parent entry, so a separate SwiftData relationship graph adds no value. A small Keychain blob protects biometric templates and supports atomic single/all deletion. The existing `KeychainSecretStore` cannot be reused because it explicitly synchronizes items.

**Rejected alternatives**:

- Parallel passive-history database: duplicates query/export/UI paths.
- One SwiftData row per speaker region: no independent query requirement.
- iCloud-synchronized voice profiles: not required and expands biometric-data scope.

## Decision 9: Defaults change without replacing working active pipelines

**Decision**: Make FunASR Nano the Mac default and FunASR Realtime the iPhone default. Remove SenseVoice cases and UI, but retain the SherpaOnnx runtime surface used by speaker embeddings. Preserve explicit supported Mac engine choices.

**Rationale**: Mac already has a Nano file service; iPhone already has the Realtime streaming engine. The smallest reliable change is default/migration/composition cleanup, not a new universal ASR layer. Mac onboarding must also stop overriding the enum default through language routing.

**Rejected alternatives**:

- Remove SherpaOnnxPackage together with SenseVoice: breaks the selected durable speaker verifier.
- Move FluidAudio into shared StetEngine for symmetry: passive processing remains Mac-only.
- Keep dead SenseVoice enum cases for compatibility: leaves unsupported choices and maintenance branches; retired stored values should migrate explicitly.

## Primary References

- Pinned local FluidAudio source and documentation at revision `0346057d8245b5e7ace6965d499f85d93e803ef1`, especially `Documentation/Diarization/GettingStarted.md`, `Documentation/Diarization/Sortformer.md`, `Sources/FluidAudio/VAD/VadManager+Streaming.swift`, and `Sources/FluidAudio/Diarizer/DiarizerTimeline.swift`.
- [FluidAudio repository](https://github.com/FluidInference/FluidAudio) for upstream project context.
- [SherpaOnnx speaker embedding C API](https://k2-fsa.github.io/sherpa/onnx/c-api/html/speaker_embedding.html) for the installed CAMPPlus extraction surface.
- [3D-Speaker repository](https://github.com/modelscope/3D-Speaker) for the CAMPPlus model family and Apache-2.0 licensing.
- Existing Stet paths: `MacCaptureAudioFileRecorder`, `MacRecordingFileSupport`, `ConfigurableSpeechService`, `FunASRNanoRecognizer`, `FunASRRealtimeEngine`, `HistoryEntry`, and `DictationHistoryService`.
