#if os(macOS)
    import Combine
    import Foundation

    @MainActor
    final class RuntimePermissionFailureViewModel: ObservableObject {
        @Published private(set) var shouldDismiss = false

        private let coordinator: any MacPermissionsCoordinating
        private var cancellables = Set<AnyCancellable>()

        init(coordinator: any MacPermissionsCoordinating) {
            self.coordinator = coordinator
            coordinator.updates
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    guard let self else { return }
                    self.objectWillChange.send()
                    self.shouldDismiss = self.hasRequiredPermissions
                }
                .store(in: &cancellables)
        }

        var hasRequiredPermissions: Bool {
            !coordinator.microphoneAccessNeedsAttention && !coordinator.autoPasteAccessNeedsAttention
        }

        var messageText: String {
            "Stet can't start this action because microphone and input control permissions are required."
        }

        var microphoneButtonTitle: String {
            coordinator.microphonePermissionActionTitle
        }

        var inputControlButtonTitle: String {
            "Grant Input Control"
        }

        func resolveMicrophoneAccess() {
            coordinator.resolveMicrophoneAccess()
        }

        func requestInputControlAccess() {
            coordinator.requestAutoPasteAccess()
        }
    }
#endif
