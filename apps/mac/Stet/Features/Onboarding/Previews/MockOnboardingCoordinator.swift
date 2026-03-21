#if os(macOS)
import SwiftUI
import Combine

final class MockOnboardingCoordinator: MacPermissionsCoordinating {
    var updates: AnyPublisher<Void, Never> = PassthroughSubject<Void, Never>().eraseToAnyPublisher()
    
    @Published var mockStep: MacOnboardingStep
    @Published var mockMode: MacOnboardingMode?
    
    var autoPasteStatusText: String = "Granted"
    var microphoneAccessStatusText: String = "Granted"
    var microphoneAccessNeedsAttention: Bool = false
    var microphonePermissionActionTitle: String = "Grant"
    var autoPasteAccessNeedsAttention: Bool = false
    
    var onboardingStep: MacOnboardingStep { mockStep }
    var onboardingMode: MacOnboardingMode? { mockMode }
    
    init(step: MacOnboardingStep = .welcome, mode: MacOnboardingMode? = nil) {
        self.mockStep = step
        self.mockMode = mode
    }
    
    func requestAutoPasteAccess() {}
    func resolveMicrophoneAccess() {}
    func openAccessibilitySettings() {}
    
    func advanceOnboarding() {
        mockStep = MacOnboardingStep(rawValue: mockStep.rawValue + 1) ?? .done
    }
    func retreatOnboarding() {
        mockStep = MacOnboardingStep(rawValue: mockStep.rawValue - 1) ?? .welcome
    }
    func chooseOnboardingMode(_ mode: MacOnboardingMode) {
        self.mockMode = mode
        advanceOnboarding()
    }
}

#endif
