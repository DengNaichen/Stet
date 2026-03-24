import Combine
import Foundation
import Testing

@testable import Stet

@MainActor
@Suite("Mac Dictation Panel View Model")
struct MacDictationPanelViewModelTests {
    final class StubPanelModel: MacDictationPanelCoordinating {
        private let updatesSubject = PassthroughSubject<Void, Never>()

        var updates: AnyPublisher<Void, Never> {
            updatesSubject.eraseToAnyPublisher()
        }

        var dictationState: DictationState
        var statusText: String
        var recordingLevel: Double
        var detectedTargetApplication: AppInfo?

        private(set) var hidePanelCallCount = 0
        private(set) var dismissPendingCopyCallCount = 0
        private(set) var cancelActiveCaptureCallCount = 0
        private(set) var performPrimaryActionCallCount = 0

        init(
            dictationState: DictationState = .idle,
            statusText: String = "Ready",
            recordingLevel: Double = 0.0
        ) {
            self.dictationState = dictationState
            self.statusText = statusText
            self.recordingLevel = recordingLevel
        }

        func emitUpdate() {
            updatesSubject.send(())
        }

        func hidePanel() {
            hidePanelCallCount += 1
        }

        func dismissPendingCopy() {
            dismissPendingCopyCallCount += 1
        }

        func cancelActiveCapture() {
            cancelActiveCaptureCallCount += 1
        }

        func performPrimaryAction() {
            performPrimaryActionCallCount += 1
        }
    }

    @Test func initialStateIsPulledFromAppModel() {
        let appModel = StubPanelModel(
            dictationState: .clipboardPending("hello"),
            statusText: "Ready to paste",
            recordingLevel: 0.64
        )
        appModel.detectedTargetApplication = AppInfo(
            bundleIdentifier: "com.apple.TextEdit",
            localizedName: "TextEdit",
            processIdentifier: 42,
            isOwnHostApplication: false,
            runningApplication: nil
        )
        let viewModel = MacDictationPanelViewModel(appModel: appModel)

        #expect(viewModel.state == .clipboardPending("hello"))
        #expect(viewModel.statusText == "Ready to paste")
        #expect(viewModel.recordingLevel == 0)
        #expect(viewModel.detectedTargetApplication?.bundleIdentifier == "com.apple.TextEdit")
    }

    @Test func appModelUpdatesArePropagatedToPublishedProperties() async {
        let appModel = StubPanelModel(
            dictationState: .idle,
            statusText: "Listening",
            recordingLevel: 0.2
        )
        let viewModel = MacDictationPanelViewModel(appModel: appModel)

        appModel.dictationState = .listening
        appModel.statusText = "Listening..."
        appModel.recordingLevel = 0.92
        appModel.detectedTargetApplication = AppInfo(
            bundleIdentifier: "com.apple.Terminal",
            localizedName: "Terminal",
            processIdentifier: 77,
            isOwnHostApplication: false,
            runningApplication: nil
        )
        appModel.emitUpdate()

        #expect(await TestSupport.eventually {
            viewModel.state == .listening &&
            viewModel.statusText == "Listening..." &&
            viewModel.recordingLevel > 0 &&
            viewModel.detectedTargetApplication?.bundleIdentifier == "com.apple.Terminal"
        })
    }

    @Test func forwardingActionsCallThroughToAppModel() {
        let appModel = StubPanelModel()
        let viewModel = MacDictationPanelViewModel(appModel: appModel)

        viewModel.hidePanel()
        viewModel.dismissPendingCopy()
        viewModel.cancelActiveCapture()
        viewModel.performPrimaryAction()

        #expect(appModel.hidePanelCallCount == 1)
        #expect(appModel.dismissPendingCopyCallCount == 1)
        #expect(appModel.cancelActiveCaptureCallCount == 1)
        #expect(appModel.performPrimaryActionCallCount == 1)
    }

    @Test func configurationFailuresAreSurfacedThroughPanelStatus() async {
        let requirements = [
            ProviderConfigurationRequirement(step: .transcription, provider: .groq),
            ProviderConfigurationRequirement(step: .rewrite, provider: .openAI)
        ]
        let appModel = StubPanelModel()
        let viewModel = MacDictationPanelViewModel(appModel: appModel)

        appModel.dictationState = .error(.missingProviderConfiguration(requirements: requirements))
        appModel.statusText = DictationFailure.missingProviderConfiguration(requirements: requirements).statusText
        appModel.emitUpdate()

        #expect(await TestSupport.eventually {
            viewModel.state == .error(.missingProviderConfiguration(requirements: requirements)) &&
            viewModel.statusText == "Provider configuration required"
        })
    }
}
