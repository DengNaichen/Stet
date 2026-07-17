#if os(macOS)
    import Combine
    import Foundation

    @MainActor
    final class MacDictationCommandsViewModel: ObservableObject {
        private let coordinator: any MacDictationCommandsCoordinating
        private var cancellables = Set<AnyCancellable>()

        init(coordinator: any MacDictationCommandsCoordinating) {
            self.coordinator = coordinator
            coordinator.updates
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.objectWillChange.send()
                }
                .store(in: &cancellables)
        }

        var menuBarSymbolName: String {
            coordinator.menuBarSymbolName
        }

        var primaryButtonTitle: String {
            coordinator.primaryButtonTitle
        }

        var panelButtonTitle: String {
            coordinator.panelButtonTitle
        }

        func performPrimaryAction() {
            coordinator.performPrimaryAction()
        }

        func togglePanel() {
            coordinator.togglePanel()
        }
    }
#endif
