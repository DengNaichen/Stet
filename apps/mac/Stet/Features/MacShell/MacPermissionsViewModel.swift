#if os(macOS)
import Combine
import Foundation

@MainActor
final class MacPermissionsViewModel: ObservableObject {
    private let coordinator: any MacPermissionsCoordinating
    private var cancellables = Set<AnyCancellable>()

    init(coordinator: any MacPermissionsCoordinating) {
        self.coordinator = coordinator
        coordinator.updates
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    var autoPasteStatusText: String {
        coordinator.autoPasteStatusText
    }

    var microphoneAccessStatusText: String {
        coordinator.microphoneAccessStatusText
    }

    var microphoneAccessNeedsAttention: Bool {
        coordinator.microphoneAccessNeedsAttention
    }

    var microphonePermissionActionTitle: String {
        coordinator.microphonePermissionActionTitle
    }

    var autoPasteAccessNeedsAttention: Bool {
        coordinator.autoPasteAccessNeedsAttention
    }

    func requestAutoPasteAccess() {
        coordinator.requestAutoPasteAccess()
    }

    func resolveMicrophoneAccess() {
        coordinator.resolveMicrophoneAccess()
    }

    func openAccessibilitySettings() {
        coordinator.openAccessibilitySettings()
    }
}
#endif
