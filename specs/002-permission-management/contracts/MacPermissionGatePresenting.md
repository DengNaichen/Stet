# Contract: MacPermissionGatePresenting

## Purpose

Defines the runtime presentation interface for the standalone permission-failure window.

## Consumers

- `MacAppSessionController`

## Surface

```swift
@MainActor
protocol MacPermissionGatePresenting: AnyObject {
    func show(appModel: any MacPermissionsCoordinating)
    func hide()
}
```

## Contract Guarantees

### show(appModel:)

- Presents the runtime permission-failure surface for the current permission state.
- Reuses the existing visible gate if one is already shown rather than creating a duplicate window.
- Activates the app so the recovery surface is visible to the user.

### hide()

- Closes the runtime permission-failure surface if it is visible.
- Is safe to call when no gate is currently shown.

## Notes

- The presentation surface is intentionally separate from onboarding.
- Consumers are expected to call `show(appModel:)` only for blocked runtime actions that cannot proceed because permissions are missing.
