# Contract: MacPermissionsCoordinating

## Purpose

Defines the shared permission coordination surface used by onboarding, the runtime permission gate, and the macOS app coordinator.

## Consumers

- `MacAppModel`
- `MacAppSessionController`
- `OnboardingViewModel`
- `RuntimePermissionFailureViewModel`

## Surface

```swift
@MainActor
protocol MacPermissionsCoordinating: MacAppStatusObserving {
    var autoPasteStatusText: String { get }
    var microphoneAccessStatusText: String { get }
    var microphoneAccessNeedsAttention: Bool { get }
    var microphonePermissionActionTitle: String { get }
    var autoPasteAccessNeedsAttention: Bool { get }
    var onboardingStep: MacOnboardingStep { get }
    var onboardingMode: MacOnboardingMode? { get }

    func requestAutoPasteAccess()
    func resolveMicrophoneAccess()
    func openAccessibilitySettings()
    func chooseOnboardingMode(_ mode: MacOnboardingMode)
    func selectOnboardingAppearanceTheme(_ theme: MacDictationVisualTheme)
    func applyOnboardingAppearanceTheme()
    func advanceOnboarding()
    func retreatOnboarding()
    func completeAPIKeyOnboarding(provider: DictationProvider)
    func finishOnboarding()
}
```

## Contract Guarantees

- `updates` on `MacAppStatusObserving` publishes when permission-relevant state changes.
- `microphoneAccessStatusText` and `microphonePermissionActionTitle` reflect the current microphone permission state.
- `autoPasteStatusText` and `autoPasteAccessNeedsAttention` reflect the current input control / accessibility access state.
- `requestAutoPasteAccess()` and `openAccessibilitySettings()` delegate to the existing recovery path used by the app.
- `resolveMicrophoneAccess()` either requests permission in-app when possible or routes the user to System Settings when a direct request is not available.
- `onboardingStep` and `onboardingMode` allow the onboarding UI to gate permission completion without duplicating permission state.

## Notes

- This contract exposes the permission surface that the app already uses; it does not persist permission grants.
- The same coordinator powers both onboarding guidance and runtime recovery.
