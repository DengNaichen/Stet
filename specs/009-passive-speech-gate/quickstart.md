# Quickstart: Validate the Passive Speech Gate Design

## Prerequisites

- Xcode stable at `/Applications/Xcode.app` for Mac builds/tests.
- Xcode Beta configured as expected by the repository's `make ios-build` target.
- Microphone permission granted to the Mac app for manual scenarios.
- FunASR Nano, FluidAudio Silero/Sortformer, and the CAMPPlus speaker model installed through their app model managers. Model payloads must not be committed.
- One enrolled owner profile from several clean clips. Known profiles require explicit consent from the recorded person.

## Automated validation

From the monorepo root:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer make lint
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer make test
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer make build
make ios-build
make verify-public
```

The focused passive suite must also cover these deterministic cases with fake audio frames, clock, verifier, diarizer, and Nano service:

1. Sixty minutes of silence produces zero verifier, diarizer, ASR, and history calls.
2. Other-only speech expires within one second after the 15-second deadline, keeps bounded memory, and creates no entry.
3. Other then owner within 15 seconds replays the retained opening in order and invokes ASR exactly once per finalized turn.
4. Owner then other keeps later other turns until the 10-second inactivity or 60-second owner-absence deadline.
5. Hotkey takeover during pending discards pending; takeover during relevant seals only the pre-boundary interval; active and passive frame IDs never intersect.
6. A 30-second hard-cap split remains ordered and contains no missing or duplicate sample range.
7. Low identity scores and overlaps are unresolved; unknown speakers are never forced to a known profile.
8. VAD, verification, diarization, ASR, permission, and device failures clear transient data and allow the next valid utterance after recovery.
9. Existing history migrates to active capture with empty regions; a retired SenseVoice preference migrates to Nano on Mac and Realtime on iPhone.
10. Deleting a profile removes its local Keychain centroid and does not rewrite historical display-name snapshots.

## Real-voice calibration

Use the existing `Public/Stet/scripts/speaker_verification_probe.py` corpus workflow to measure cosine-score distributions for the owner, each enrolled known speaker, and multiple unknown voices. Treat the output as similarity, not probability.

The production threshold and runner-up margin pass only when the controlled corpus satisfies:

- at least 90% owner admission recall;
- at least 95% other-only rejection;
- at least 90% correct label on distinguishable enrolled-known-speaker regions;
- every below-threshold or ambiguous match remains `other` or `unresolved`.

Then run these manual Mac scenarios:

| Scenario | Expected result |
|---|---|
| Quiet desk | Passive microphone indicator remains visible; no history entry |
| Nearby video/other-only conversation | Audio expires; no Nano invocation or history entry |
| Colleague speaks, owner replies within 15 s | One passive entry contains opening then reply with labels |
| Owner speaks first | Relevant conversation opens without clipping the first word |
| Owner stops participating while others continue | Entry closes no later than 60 s after last owner match |
| Two people overlap | One unresolved overlap region; no duplicated text/audio |
| Hold hotkey during pending/relevant speech | Active accepts every voice; no duplicate passive interval |
| Release hotkey | Fresh passive epoch starts immediately with no old context |
| Turn passive listening off | Passive microphone use stops; hotkey dictation still records and transcribes |
| Relaunch while passive is off, then turn it on | The off preference persists; enabling restores passive listening when the owner profile and models are ready |

## Long-run and privacy checks

- Run an eight-hour synthetic mixed session while tracking resident memory and Energy Log. The ring remains bounded, silence runs only VAD, and other-only speech invokes no diarizer/ASR.
- Inspect the app container after other-only, accepted, failed, cancelled, and relaunched sessions. No pending or accepted temporary WAV remains after terminal cleanup.
- Inspect Keychain behavior with synchronization disabled. Only model metadata and aggregate centroids exist; no enrollment samples or per-clip embeddings exist.
- Confirm passive entries are stored in history only: no rewrite request, paste/copy action, target application, or cloud upload occurs.
