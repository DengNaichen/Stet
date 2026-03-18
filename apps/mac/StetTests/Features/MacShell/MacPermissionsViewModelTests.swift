#if os(macOS)
import Combine
import Foundation
import Testing

@testable import Stet

@MainActor
private final class TestMacPermissionsCoordinator: MacPermissionsCoordinating {
    private let updatesSubject = PassthroughSubject<Void, Never>()
    let updates: AnyPublisher<Void, Never>

    var autoPasteStatusText: String
    var microphoneAccessStatusText: String
    var microphoneAccessNeedsAttention: Bool
    var microphonePermissionActionTitle: String
    var autoPasteAccessNeedsAttention: Bool

    private(set) var requestAutoPasteAccessCallCount = 0
    private(set) var resolveMicrophoneAccessCallCount = 0
    private(set) var openAccessibilitySettingsCallCount = 0

    init(
        autoPasteStatusText: String,
        microphoneAccessStatusText: String,
        microphoneAccessNeedsAttention: Bool,
        microphonePermissionActionTitle: String,
        autoPasteAccessNeedsAttention: Bool
    ) {
        self.autoPasteStatusText = autoPasteStatusText
        self.microphoneAccessStatusText = microphoneAccessStatusText
        self.microphoneAccessNeedsAttention = microphoneAccessNeedsAttention
        self.microphonePermissionActionTitle = microphonePermissionActionTitle
        self.autoPasteAccessNeedsAttention = autoPasteAccessNeedsAttention
        self.updates = updatesSubject.eraseToAnyPublisher()
    }

    func emitUpdate() {
        updatesSubject.send(())
    }

    func requestAutoPasteAccess() {
        requestAutoPasteAccessCallCount += 1
    }

    func resolveMicrophoneAccess() {
        resolveMicrophoneAccessCallCount += 1
    }

    func openAccessibilitySettings() {
        openAccessibilitySettingsCallCount += 1
    }
}

@MainActor
@Suite("Mac Permissions View Model", .serialized)
struct MacPermissionsViewModelTests {
    private func makeSut() -> (
        viewModel: MacPermissionsViewModel,
        coordinator: TestMacPermissionsCoordinator
    ) {
        let coordinator = TestMacPermissionsCoordinator(
            autoPasteStatusText: "Auto-paste not ready",
            microphoneAccessStatusText: "Microphone blocked",
            microphoneAccessNeedsAttention: true,
            microphonePermissionActionTitle: "Resolve microphone",
            autoPasteAccessNeedsAttention: true
        )

        return (MacPermissionsViewModel(coordinator: coordinator), coordinator)
    }

    @Test func computedPropertiesReflectCoordinatorState() {
        let (viewModel, coordinator) = makeSut()

        #expect(viewModel.autoPasteStatusText == coordinator.autoPasteStatusText)
        #expect(viewModel.microphoneAccessStatusText == coordinator.microphoneAccessStatusText)
        #expect(viewModel.microphoneAccessNeedsAttention == coordinator.microphoneAccessNeedsAttention)
        #expect(viewModel.microphonePermissionActionTitle == coordinator.microphonePermissionActionTitle)
        #expect(viewModel.autoPasteAccessNeedsAttention == coordinator.autoPasteAccessNeedsAttention)
    }

    @Test func updatesDriveViewRefreshForCoordinatorChanges() async {
        let (viewModel, coordinator) = makeSut()

        var changeCount = 0
        var changeCancellable: AnyCancellable?
        changeCancellable = viewModel.objectWillChange.sink {
            changeCount += 1
        }

        coordinator.autoPasteStatusText = "Auto-paste ready"
        coordinator.microphoneAccessNeedsAttention = false
        coordinator.emitUpdate()

        #expect(await TestSupport.eventually { changeCount == 1 })

        _ = changeCancellable

        #expect(viewModel.autoPasteStatusText == "Auto-paste ready")
        #expect(viewModel.microphoneAccessNeedsAttention == false)
    }

    @Test func requestAutoPasteAccessForwardsToCoordinator() {
        let (viewModel, coordinator) = makeSut()

        viewModel.requestAutoPasteAccess()

        #expect(coordinator.requestAutoPasteAccessCallCount == 1)
    }

    @Test func resolveMicrophoneAccessForwardsToCoordinator() {
        let (viewModel, coordinator) = makeSut()

        viewModel.resolveMicrophoneAccess()

        #expect(coordinator.resolveMicrophoneAccessCallCount == 1)
    }

    @Test func openAccessibilitySettingsForwardsToCoordinator() {
        let (viewModel, coordinator) = makeSut()

        viewModel.openAccessibilitySettings()

        #expect(coordinator.openAccessibilitySettingsCallCount == 1)
    }
}
#endif
