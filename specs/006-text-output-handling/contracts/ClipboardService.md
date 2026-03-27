# Contract: ClipboardService

## Overview

`ClipboardService` is the boundary for writing plain text to the system clipboard during text output handling.

## Responsibility

- Write a text payload into the clipboard
- Indicate whether the write is transient so the output pipeline can treat it as a temporary override
- Report success or failure to the caller

## Interface

```swift
@MainActor
protocol ClipboardService {
    @discardableResult
    func copy(_ text: String, transient: Bool) -> Bool
}

extension ClipboardService {
    @discardableResult
    func copy(_ text: String) -> Bool
}
```

## Behavior Expectations

- The service MUST accept the text exactly as provided by the caller.
- The service MUST return `false` when the clipboard write cannot be completed.
- The service SHOULD remain agnostic about how the caller uses the clipboard afterward.
- The service MUST not claim any restore behavior; restore is handled by the output workflow.

## Notes

- On macOS, the concrete implementation may attach source metadata or a transient marker for diagnostics and temporary override flows.
- Those markers are implementation details and are not part of the contract surface.
