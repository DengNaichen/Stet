#if os(macOS)
    import Testing

    @testable import Stet

    @MainActor
    @Suite("Mac MCP Settings View Model")
    struct MacMCPSettingsViewModelTests {
        @Test func copiesPersistentSetupPrompt() {
            let clipboard = TestClipboardService()
            let viewModel = MacMCPSettingsViewModel(clipboardService: clipboard)

            viewModel.copySetupPrompt()

            #expect(viewModel.copySucceeded)
            #expect(clipboard.copiedTexts == [MacMCPSettingsViewModel.setupPrompt])
            #expect(clipboard.transientFlags == [false])
            #expect(MacMCPSettingsViewModel.setupPrompt.contains("http://127.0.0.1:49321/mcp"))
            #expect(MacMCPSettingsViewModel.setupPrompt.contains("Preserve all existing MCP servers"))
        }

        @Test func forwardsToggleAndTracksServerState() async {
            let appModel = TestMacMCPSettingsAppModel()
            let viewModel = MacMCPSettingsViewModel(clipboardService: TestClipboardService())
            viewModel.configure(appModel: appModel)

            viewModel.setEnabled(true)
            let started = await TestSupport.eventuallyAsync {
                await MainActor.run { appModel.enabledChanges == [true] }
            }

            #expect(started)
            #expect(viewModel.state == .running)
        }
    }

    @MainActor
    private final class TestMacMCPSettingsAppModel: MacMCPSettingsAppModeling {
        var mcpServerState: StetMCPServerState = .disabled
        var enabledChanges: [Bool] = []
        private var stateHandler: (@MainActor (StetMCPServerState) -> Void)?

        func setMCPServerEnabled(_ enabled: Bool) async -> StetMCPServerState {
            enabledChanges.append(enabled)
            mcpServerState = enabled ? .running : .disabled
            stateHandler?(mcpServerState)
            return mcpServerState
        }

        func setMCPServerStateHandler(_ handler: @escaping @MainActor (StetMCPServerState) -> Void) {
            stateHandler = handler
            handler(mcpServerState)
        }
    }
#endif
