# Implementation Plan: Text Output Handling

## Overview

This implementation plan tracks the work required to deliver the macOS text output handling flow for Stet. The current architecture already has the core path in place: clipboard-backed auto-paste, best-effort pasteboard restoration, and fallback to clipboard when text injection verification fails. The remaining work is mainly in failure surfacing, stronger correctness guarantees, and broader test coverage.

The plan is organized in two layers:
- Foundation tasks that are already implemented and should remain stable
- Remaining tasks needed to fully satisfy the requirements and target design

---

## Tasks

- [x] 1. Establish core text output orchestration
  - [x] 1.1 Implement capture completion coordination in `apps/mac/Stet/App/Workflows/MacDictationCaptureCoordinator.swift`
    - Coordinate clipboard copy, auto-paste attempt, pasteboard protection, and completion outcomes
    - Support `CaptureSettings` with `shouldCopyToClipboard`, `shouldAutoPaste`, and `shouldRevealPanelOnCapture`
    - Handle successful paste, failed paste, and no-output branches
    - _Requirements: 1.1, 1.2, 2.1, 3.1, 4.1, 5.5_

  - [x] 1.2 Implement clipboard-backed injection flow in `apps/mac/Stet/Core/TextInput/TextInjectionService.swift`
    - Simulate `Cmd+V` into the target application
    - Capture focused-element snapshots before and after paste
    - Verify paste success by detecting focused-element mutation
    - Support selection replacement via `replaceSelectedText`
    - _Requirements: 1.5, 3.1, 3.2, 3.3, 3.4_

  - [x] 1.3 Implement system clipboard writing in `apps/mac/Stet/Core/Clipboard/ClipboardService.swift`
    - Write plain text to the general pasteboard
    - Mark transient clipboard content for temporary override flows
    - Tag source bundle identifier for diagnostics
    - _Requirements: 2.1, 2.3, 2.4, 4.1_

  - [x] 1.4 Implement best-effort pasteboard restoration in `apps/mac/Stet/Core/Clipboard/PasteboardRestoreCoordinator.swift`
    - Capture the original pasteboard snapshot before temporary override
    - Restore after a delayed success path if the pasteboard still matches the temporary snapshot
    - Restore immediately on paste failure
    - Preserve multi-item and multi-type pasteboard payloads on a best-effort basis
    - _Requirements: 4.1, 4.2, 4.3, 4.4_

  - [x] 1.5 Add empty-text guards in `apps/mac/Stet/App/Workflows/MacDictationCaptureCoordinator.swift`, `apps/mac/Stet/App/Workflows/MacDictationWorkflowController.swift`, and `apps/mac/Stet/Core/TextInput/TextInjectionService.swift`
    - Skip output for empty or whitespace-only text
    - Return an empty-transcription failure at the workflow boundary where applicable
    - Prevent empty replacement attempts
    - _Requirements: 6.1, 6.3, 6.4_

- [x] 2. Lock in fallback behavior with tests
  - [x] 2.1 Add coordinator coverage in `apps/mac/StetTests/App/Workflows/MacDictationCaptureCoordinatorTests.swift`
    - Verify clipboard-only output
    - Verify transient copy + successful auto-paste
    - Verify failed auto-paste falls back to permanent clipboard copy
    - Verify empty text does not trigger output
    - _Requirements: 2.1, 3.1, 5.5, 6.1_

  - [x] 2.2 Add workflow coverage in `apps/mac/StetTests/App/Workflows/MacDictationWorkflowControllerTests.swift`
    - Verify dictation completion uses the coordinator path
    - Verify failed dictation completion falls back to clipboard copy
    - Verify failed selection replacement falls back to clipboard copy
    - Verify empty completion text maps to `.emptyTranscription`
    - _Requirements: 3.1, 5.5, 6.1, 6.2_

- [x] 3. Surface output failures explicitly to the user
  - [x] 3.1 Introduce an output-specific failure surface in `apps/mac/Stet/App/Workflows/MacDictationCaptureCoordinator.swift`, `apps/mac/Stet/App/Workflows/MacDictationWorkflowController.swift`, and `apps/mac/Stet/Features/Dictation/DictationFailure.swift`
    - Distinguish between clipboard write failure, permission failure, paste verification failure, and empty-text no-op
    - Stop overloading generic success/fallback paths for cases that should produce actionable UI
    - _Requirements: 5.1, 5.2, 5.3, 5.4_

  - [x] 3.2 Make clipboard writes observable in `apps/mac/Stet/Core/Clipboard/ClipboardService.swift`
    - Change the clipboard write API to report success or failure instead of being fire-and-forget
    - Plumb failures back to the coordinator
    - Add logging for clipboard write failures without logging sensitive clipboard contents
    - _Requirements: 5.1, 5.4, Reliability_

  - [x] 3.3 Add user-facing recovery messaging in `apps/mac/Stet/App/Workflows/MacAppSessionController.swift` and `apps/mac/Stet/Features/Dictation/DictationViewModel.swift`
    - Show clear guidance when input-control permissions are missing
    - Show a distinct message when paste verification fails but clipboard fallback succeeds
    - Preserve the current non-disruptive success path when fallback succeeds silently
    - _Requirements: 5.2, 5.3, 5.4_

- [x] 4. Strengthen text injection correctness
  - [x] 4.1 Replace the raw `Bool` paste result with a richer verified outcome in `apps/mac/Stet/Core/TextInput/TextInjectionService.swift`
    - Distinguish event-posted, verification-unavailable, verification-failed, and verified-success cases
    - Avoid treating “could not verify” and “verified failed” as the same condition
    - _Requirements: 1.5, 3.2, 5.3_

  - [x] 4.2 Improve focused-element verification coverage in `apps/mac/Stet/Core/TextInput/TextInjectionService.swift`
    - Support more editable control variations where `kAXValue`, `kAXSelectedText`, or `kAXSelectedTextRange` are incomplete
    - Keep the verification path best-effort rather than introducing fake preflight detection
    - _Requirements: 1.5, 3.1, 3.4, Compatibility_

  - [x] 4.3 Validate cursor and selection postconditions in `apps/mac/Stet/Core/TextInput/TextInjectionService.swift`
    - Add explicit checks for the caret ending after inserted text when AX range data is available
    - Define best-effort behavior when the target app does not expose sufficient selection metadata
    - _Requirements: 3.5_

- [x] 5. Improve pasteboard protection diagnostics
  - [x] 5.1 Add restore-path logging in `apps/mac/Stet/Core/Clipboard/PasteboardRestoreCoordinator.swift`
    - Log skipped restores when the temporary snapshot no longer matches
    - Log restore failures without recording clipboard payload contents
    - Keep restoration best-effort and non-blocking
    - _Requirements: 4.4, Reliability_

  - [x] 5.2 Add unit tests for restore edge cases in `apps/mac/StetTests/Core/Clipboard/PasteboardRestoreCoordinatorTests.swift`
    - Verify restore is skipped when the clipboard changes externally
    - Verify restore preserves multi-item payloads where possible
    - Verify immediate restore on failure still clears pending state
    - _Requirements: 4.2, 4.3, 4.4_

- [ ] 6. Expand correctness and integration tests
  - [ ] 6.1 Add integration coverage for runtime output failures in `apps/mac/StetTests/App/Workflows/MacAppSessionControllerActionTests.swift` and `apps/mac/StetTests/App/Workflows/MacDictationWorkflowControllerTests.swift`
    - Verify permission-missing flows request access and preserve the transcript
    - Verify panel reveal behavior stays consistent after fallback
    - Verify output completion state is correct for dictation and selection-replacement workflows
    - _Requirements: 5.2, 5.3, 5.5_

  - [ ]* 6.2 Add property-based tests for clipboard output integrity in `apps/mac/StetTests/Core/Clipboard/ClipboardServicePropertyTests.swift`
    - Validate round-trip integrity for multiline, Unicode, and punctuation-heavy text
    - _Requirements: 2.3, 2.4, 7.1, 7.2, 7.3_

  - [ ]* 6.3 Add property-based tests for pasteboard restoration in `apps/mac/StetTests/Core/Clipboard/PasteboardRestoreCoordinatorPropertyTests.swift`
    - Validate that unchanged temporary clipboard contents restore to the original snapshot
    - Validate that modified clipboard contents are not overwritten
    - _Requirements: 4.1, 4.2, 4.3_

  - [ ]* 6.4 Add property-based tests for text output no-op behavior in `apps/mac/StetTests/App/Workflows/MacDictationCaptureCoordinatorPropertyTests.swift`
    - Validate empty and whitespace-only text never triggers system write side effects
    - _Requirements: 6.1, 6.3_

- [x] 7. Align specification documents
  - [x] 7.1 Update `apps/mac/.kiro/specs/text-output-handling/requirements.md`
    - Tighten the product contract around automatic routing, best-effort clipboard protection, and automatic fallback
    - Remove over-strong guarantees that the system cannot actually make
    - _Requirements: Documentation alignment_

  - [x] 7.2 Update `apps/mac/.kiro/specs/text-output-handling/design.md`
    - Reframe the design around optimistic paste, focused-element verification, and clipboard fallback
    - Correct interface listings and file structure descriptions
    - Mark the document as the target implementation rather than a snapshot of current code
    - _Requirements: Documentation alignment_

- [ ] 8. Final verification checkpoint
  - [x] 8.1 Run focused macOS test validation for text output handling
    - Re-run `MacDictationCaptureCoordinatorTests`
    - Re-run `MacDictationWorkflowControllerTests`
    - Re-run clipboard and text-input unit tests after any remaining refactors
    - _Requirements: Cross-cutting validation_

  - [ ] 8.2 Confirm requirements-to-implementation traceability
    - Ensure each remaining unchecked requirement has at least one concrete implementation task and one test task
    - Update this plan if the design or requirements shift again
    - _Requirements: Process quality_

## Notes

- Tasks marked with `*` are optional property-based tests and can be deferred for MVP.
- The current codebase already satisfies the main happy path: temporary clipboard override, verified auto-paste attempt, and automatic clipboard fallback.
- The main remaining gaps are explicit failure surfacing, stronger verification semantics, and broader automated coverage.
