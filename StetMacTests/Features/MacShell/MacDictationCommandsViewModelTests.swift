#if os(macOS)
    import Combine
    import Foundation
    import Testing

    @testable import Stet

    @MainActor
    private final class TestMacDictationCommandsCoordinator: MacDictationCommandsCoordinating {
        private let updatesSubject = PassthroughSubject<Void, Never>()
        let updates: AnyPublisher<Void, Never>

        var menuBarSymbolName: String
        var primaryButtonTitle: String
        var panelButtonTitle: String

        private(set) var performPrimaryActionCallCount = 0
        private(set) var togglePanelCallCount = 0

        init(
            menuBarSymbolName: String = "mic.circle",
            primaryButtonTitle: String = "Start Dictation",
            panelButtonTitle: String = "Show Panel"
        ) {
            self.menuBarSymbolName = menuBarSymbolName
            self.primaryButtonTitle = primaryButtonTitle
            self.panelButtonTitle = panelButtonTitle
            self.updates = updatesSubject.eraseToAnyPublisher()
        }

        func emitUpdate() {
            updatesSubject.send(())
        }

        func performPrimaryAction() {
            performPrimaryActionCallCount += 1
        }

        func togglePanel() {
            togglePanelCallCount += 1
        }
    }

    @MainActor
    @Suite("Mac Dictation Commands View Model", .serialized)
    struct MacDictationCommandsViewModelTests {
        @Test func computedPropertiesReflectCoordinatorState() {
            let coordinator = TestMacDictationCommandsCoordinator()
            let viewModel = MacDictationCommandsViewModel(coordinator: coordinator)

            #expect(viewModel.menuBarSymbolName == "mic.circle")
            #expect(viewModel.primaryButtonTitle == "Start Dictation")
            #expect(viewModel.panelButtonTitle == "Show Panel")
        }

        @Test func updatesDriveViewRefreshForCoordinatorChanges() async {
            let coordinator = TestMacDictationCommandsCoordinator()
            let viewModel = MacDictationCommandsViewModel(coordinator: coordinator)

            var changeCount = 0
            var cancellable: AnyCancellable?
            cancellable = viewModel.objectWillChange.sink {
                changeCount += 1
            }

            coordinator.menuBarSymbolName = "waveform"
            coordinator.primaryButtonTitle = "Stop Dictation"
            coordinator.panelButtonTitle = "Hide Panel"
            coordinator.emitUpdate()

            #expect(await TestSupport.eventually { changeCount == 1 })

            _ = cancellable

            #expect(viewModel.menuBarSymbolName == "waveform")
            #expect(viewModel.primaryButtonTitle == "Stop Dictation")
            #expect(viewModel.panelButtonTitle == "Hide Panel")
        }

        @Test func actionsAreForwardedToCoordinator() {
            let coordinator = TestMacDictationCommandsCoordinator()
            let viewModel = MacDictationCommandsViewModel(coordinator: coordinator)

            viewModel.performPrimaryAction()
            viewModel.togglePanel()

            #expect(coordinator.performPrimaryActionCallCount == 1)
            #expect(coordinator.togglePanelCallCount == 1)
        }
    }
#endif
