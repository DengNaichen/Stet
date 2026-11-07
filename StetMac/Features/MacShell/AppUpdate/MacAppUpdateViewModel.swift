#if os(macOS)
    import Combine
    import Foundation
    import Observation

    @MainActor
    @Observable
    final class MacAppUpdateViewModel: MacAppUpdateCoordinating {
        private let coordinator: any MacAppUpdateCoordinating
        private var snapshot: MacAppUpdateSnapshot
        @ObservationIgnored private var cancellable: AnyCancellable?

        init(coordinator: any MacAppUpdateCoordinating) {
            self.coordinator = coordinator
            snapshot = coordinator.updateSnapshot
            cancellable = coordinator.updateSnapshots.sink { [weak self] in
                self?.snapshot = $0
            }
        }

        var updateSnapshot: MacAppUpdateSnapshot { snapshot }
        var updateSnapshots: AnyPublisher<MacAppUpdateSnapshot, Never> { coordinator.updateSnapshots }

        var state: MacAppUpdateState { snapshot.state }
        var isConfigured: Bool { snapshot.isConfigured }
        var isChecking: Bool { snapshot.isChecking }
        var canCheckForUpdates: Bool { snapshot.canCheckForUpdates }
        var automaticallyChecksForUpdates: Bool { snapshot.automaticallyChecksForUpdates }

        func checkForUpdates() {
            coordinator.checkForUpdates()
        }

        func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
            coordinator.setAutomaticallyChecksForUpdates(enabled)
        }
    }
#endif
