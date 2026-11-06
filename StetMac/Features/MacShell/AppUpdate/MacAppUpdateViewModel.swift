#if os(macOS)
    import Combine
    import Foundation

    @MainActor
    final class MacAppUpdateViewModel: ObservableObject, MacAppUpdateCoordinating {
        private let coordinator: any MacAppUpdateCoordinating
        private var cancellables = Set<AnyCancellable>()

        init(coordinator: any MacAppUpdateCoordinating) {
            self.coordinator = coordinator
            coordinator.updates
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.objectWillChange.send()
                }
                .store(in: &cancellables)
        }

        var updates: AnyPublisher<Void, Never> {
            objectWillChange.eraseToAnyPublisher()
        }

        var state: MacAppUpdateState { coordinator.state }
        var isConfigured: Bool { coordinator.isConfigured }
        var isChecking: Bool { coordinator.isChecking }
        var canCheckForUpdates: Bool { coordinator.canCheckForUpdates }
        var automaticallyChecksForUpdates: Bool { coordinator.automaticallyChecksForUpdates }

        func checkForUpdates() {
            coordinator.checkForUpdates()
        }

        func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
            coordinator.setAutomaticallyChecksForUpdates(enabled)
        }
    }
#endif
