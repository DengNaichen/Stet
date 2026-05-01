#if os(macOS)
    import Combine
    import StetCore
    import SwiftUI

    @MainActor
    final class MockOnboardingCoordinator: MacPermissionsCoordinating {
        private let updatesSubject = PassthroughSubject<Void, Never>()

        var updates: AnyPublisher<Void, Never> {
            updatesSubject.eraseToAnyPublisher()
        }

        var mockStep: MacOnboardingStep {
            didSet { notifyChange() }
        }

        var mockMode: MacOnboardingMode? {
            didSet { notifyChange() }
        }

        var autoPasteStatusText: String {
            didSet { notifyChange() }
        }

        var microphoneAccessStatusText: String {
            didSet { notifyChange() }
        }

        var microphoneAccessNeedsAttention: Bool {
            didSet { notifyChange() }
        }

        var microphonePermissionActionTitle: String {
            didSet { notifyChange() }
        }

        var autoPasteAccessNeedsAttention: Bool {
            didSet { notifyChange() }
        }

        var shortcutTestDetectedPress: Bool {
            didSet { notifyChange() }
        }

        var shortcutTestCompletedRoundTrip: Bool {
            didSet { notifyChange() }
        }

        var shortcutTestPreviewText: String? {
            didSet { notifyChange() }
        }

        var canContinueShortcutOnboarding: Bool {
            didSet { notifyChange() }
        }

        var firstSuccessPreviewText: String? {
            didSet { notifyChange() }
        }

        var firstSuccessFailureMessage: String? {
            didSet { notifyChange() }
        }

        var canContinueFirstSuccessOnboarding: Bool {
            didSet { notifyChange() }
        }

        var canSkipFirstSuccessOnboarding: Bool {
            didSet { notifyChange() }
        }

        var canFinishAppearanceOnboarding: Bool {
            didSet { notifyChange() }
        }

        var shortcutSummaryText: String = "Shortcut configured" {
            didSet { notifyChange() }
        }

        var onboardingStep: MacOnboardingStep { mockStep }
        var onboardingMode: MacOnboardingMode? { mockMode }

        init(step: MacOnboardingStep = .language, mode: MacOnboardingMode? = nil) {
            self.mockStep = step
            self.mockMode = mode
            self.autoPasteStatusText = "Granted"
            self.microphoneAccessStatusText = "Granted"
            self.microphoneAccessNeedsAttention = false
            self.microphonePermissionActionTitle = "Grant"
            self.autoPasteAccessNeedsAttention = false
            self.autoPasteAccessNeedsAttention = false
            self.shortcutTestDetectedPress = true
            self.shortcutTestCompletedRoundTrip = true
            self.shortcutTestPreviewText = "Preview transcription looks good."
            self.canContinueShortcutOnboarding = true
            self.firstSuccessPreviewText = "Tomorrow at 3 PM, help me book it."
            self.firstSuccessFailureMessage = nil
            self.canContinueFirstSuccessOnboarding = true
            self.canSkipFirstSuccessOnboarding = true
            self.canFinishAppearanceOnboarding = false
            configurePreviewState(for: step)
        }

        func requestAutoPasteAccess() {
            autoPasteStatusText = "Granted"
        }

        func resolveMicrophoneAccess() {
            microphoneAccessStatusText = "Granted"
        }

        func openAccessibilitySettings() {}

        func chooseOnboardingMode(_ mode: MacOnboardingMode) {
            mockMode = mode
            mockStep = .permissions
        }

        func selectOnboardingAppearanceTheme(_ theme: MacDictationVisualTheme) {
            canFinishAppearanceOnboarding = false
            _ = theme
        }

        func applyOnboardingAppearanceTheme() {
            canFinishAppearanceOnboarding = true
        }

        func advanceOnboarding() {
            switch mockStep {
            case .language:
                mockStep = .permissions
            case .permissions:
                mockStep = .shortcut
            case .shortcut:
                mockStep = .firstSuccess
            case .firstSuccess:
                mockStep = .appearance
            case .done:
                break
            case .appearance:
                mockStep = .done
            }
        }

        func retreatOnboarding() {
            switch mockStep {
            case .language:
                break
            case .permissions:
                mockStep = .language
            case .shortcut:
                mockStep = .permissions
            case .firstSuccess:
                mockStep = .shortcut
            case .done:
                mockStep = .firstSuccess
            case .appearance:
                mockStep = .firstSuccess
            }
        }

        func finishOnboarding() {
            mockStep = .done
        }

        private func configurePreviewState(for step: MacOnboardingStep) {
            switch step {
            case .language:
                break
            case .permissions:
                break
            case .shortcut:
                mockStep = .shortcut
            case .firstSuccess:
                mockStep = .firstSuccess
            case .done:
                mockStep = .done
            case .appearance:
                mockStep = .appearance
            }
        }

        private func notifyChange() {
            updatesSubject.send(())
        }
    }

    struct PreviewOnboardingAPIKeyValidationService: ProviderCredentialValidating {
        func validateCredential(apiKey _: String, provider _: DictationProvider) async throws {}
    }

#endif
