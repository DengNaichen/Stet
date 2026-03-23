#if os(macOS)
import Combine
internal import Auth
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

    var relaySessionEmail: String? {
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

    var shortcutSummaryText: String = "Shortcut configured" {
        didSet { notifyChange() }
    }

    var onboardingStep: MacOnboardingStep { mockStep }
    var onboardingMode: MacOnboardingMode? { mockMode }

    init(step: MacOnboardingStep = .mode, mode: MacOnboardingMode? = nil) {
        self.mockStep = step
        self.mockMode = mode
        self.autoPasteStatusText = "Granted"
        self.microphoneAccessStatusText = "Granted"
        self.microphoneAccessNeedsAttention = false
        self.microphonePermissionActionTitle = "Grant"
        self.autoPasteAccessNeedsAttention = false
        self.relaySessionEmail = "preview@stet.app"
        self.shortcutTestDetectedPress = true
        self.shortcutTestCompletedRoundTrip = true
        self.shortcutTestPreviewText = "Preview transcription looks good."
        self.canContinueShortcutOnboarding = true
        self.firstSuccessPreviewText = "Tomorrow at 3 PM, help me book it."
        self.firstSuccessFailureMessage = nil
        self.canContinueFirstSuccessOnboarding = true
        self.canSkipFirstSuccessOnboarding = true
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
        mockStep = mode == .apiKey ? .apiKey : .login
    }

    func advanceOnboarding() {
        switch mockStep {
        case .mode:
            break
        case .apiKey:
            mockStep = .permissions
        case .login:
            mockStep = .permissions
        case .permissions:
            mockStep = .shortcut
        case .shortcut:
            mockStep = .firstSuccess
        case .firstSuccess:
            mockStep = .done
        case .done:
            break
        }
    }

    func retreatOnboarding() {
        switch mockStep {
        case .mode:
            break
        case .apiKey, .login:
            mockStep = .mode
        case .permissions:
            mockStep = mockMode == .managed ? .login : .apiKey
        case .shortcut:
            mockStep = .permissions
        case .firstSuccess:
            mockStep = .shortcut
        case .done:
            mockStep = .firstSuccess
        }
    }

    func completeAPIKeyOnboarding(provider: DictationProvider) {
        mockMode = .apiKey
        mockStep = .permissions
        shortcutSummaryText = "\(provider.displayName) preview key"
    }

    func completeManagedOnboarding() {
        mockMode = .managed
        mockStep = .permissions
    }

    func finishOnboarding() {
        mockStep = .done
    }

    private func configurePreviewState(for step: MacOnboardingStep) {
        switch step {
        case .mode:
            break
        case .apiKey:
            mockMode = .apiKey
        case .login:
            mockMode = .managed
        case .permissions:
            break
        case .shortcut:
            mockStep = .shortcut
        case .firstSuccess:
            mockStep = .firstSuccess
        case .done:
            mockStep = .done
        }
    }

    private func notifyChange() {
        updatesSubject.send(())
    }
}

@MainActor
final class PreviewOnboardingSupabaseService: OnboardingSupabaseAuthenticating {
    var hasCurrentSession = false

    func signIn(email _: String, password _: String) async throws {
        hasCurrentSession = true
    }

    func signIn(provider _: Provider) async throws {
        hasCurrentSession = true
    }
}

struct PreviewOnboardingAPIKeyValidationService: OnboardingAPIKeyValidating {
    func validate(apiKey _: String, provider _: DictationProvider) async throws {}
}

#endif
