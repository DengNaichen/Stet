# Contract: TextInjectionService

## Overview

`TextInjectionService` is the boundary for simulating text input into the target app and for handling selection replacement workflows.

## Responsibility

- Report whether the system can currently simulate input
- Request or open permissions required for input injection
- Paste the clipboard into the target application
- Replace selected text when the workflow asks for in-place rewrite
- Provide best-effort access to the current selected text

## Interface

```swift
@MainActor
struct TextInjectionAccessState: Equatable {
    let hasAccessibilityAccess: Bool
    let hasPostEventAccess: Bool
    var canSimulateInput: Bool { get }
}

@MainActor
enum TextInjectionOutcome: Equatable {
    case verifiedSuccess
    case eventPostedVerificationUnavailable
    case verificationFailed
    case eventPostFailed
}

@MainActor
enum TextReplacementOutcome: Equatable {
    case replaced
    case clipboardWriteFailed
    case injectionFailed(TextInjectionOutcome)
}

@MainActor
protocol TextInjectionService {
    var accessState: TextInjectionAccessState { get }
    var isAvailable: Bool { get }

    func requestAccess()
    func requestAccessIfNeeded()
    func openAccessibilitySettings()
    func pasteClipboard(into application: NSRunningApplication?) async -> TextInjectionOutcome
    func selectedText() -> String?
    func replaceSelectedText(
        _ text: String,
        into application: NSRunningApplication?,
        keepResultInClipboard: Bool
    ) async -> TextReplacementOutcome
}
```

## Behavior Expectations

- The service MUST treat simulated input as permission-gated.
- The service MUST distinguish verified success from unverifiable or failed paste attempts.
- The service MUST evaluate paste verification against the target application's focused element after target-app activation has been given a chance to settle.
- The service SHOULD use a bounded verification window rather than a single immediate metadata read when inferring paste success.
- The service SHOULD return best-effort results when the target app does not expose enough metadata for full verification.
- The service MUST not promise that an input field is detected ahead of time.
- The service MUST allow callers to preserve the result in clipboard when a replacement or paste path needs recovery support.

## Notes

- The concrete implementation may use accessibility focus data, simulated key events, target-app activation, bounded verification polling, and clipboard snapshotting to infer whether the paste or replacement succeeded.
- Those mechanics are implementation details and are not part of the public contract surface.
