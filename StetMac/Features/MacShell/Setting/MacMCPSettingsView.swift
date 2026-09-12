#if os(macOS)
    import Combine
    import SwiftUI

    @MainActor
    protocol MacMCPSettingsAppModeling: AnyObject {
        var mcpServerState: StetMCPServerState { get }
        func setMCPServerEnabled(_ enabled: Bool) async -> StetMCPServerState
        func setMCPServerStateHandler(_ handler: @escaping @MainActor (StetMCPServerState) -> Void)
    }

    @MainActor
    final class MacMCPSettingsViewModel: ObservableObject {
        static let setupPrompt = """
            Configure the Stet MCP server for this coding agent.

            Server name: stet
            Transport: HTTP
            URL: http://127.0.0.1:49321/mcp

            Use the MCP configuration format and location supported by the current coding agent. Preserve all existing MCP servers and settings. After updating the configuration, validate the configuration syntax, connect to the server, and call an available Stet tool to verify the integration. If the client must be reloaded, tell me exactly what to do.
            """

        @Published private(set) var state: StetMCPServerState = .disabled
        @Published private(set) var copySucceeded = false

        private let clipboardService: any ClipboardService
        private weak var appModel: (any MacMCPSettingsAppModeling)?

        init(clipboardService: (any ClipboardService)? = nil) {
            self.clipboardService = clipboardService ?? SystemClipboardService()
        }

        var isEnabled: Bool {
            state != .disabled
        }

        var isTransitioning: Bool {
            state == .starting
        }

        func configure(appModel: any MacMCPSettingsAppModeling) {
            self.appModel = appModel
            state = appModel.mcpServerState
            appModel.setMCPServerStateHandler { [weak self] state in
                self?.state = state
            }
        }

        func setEnabled(_ enabled: Bool) {
            Task { [weak self] in
                guard let self, let appModel = self.appModel else { return }
                state = await appModel.setMCPServerEnabled(enabled)
            }
        }

        func copySetupPrompt() {
            copySucceeded = clipboardService.copy(Self.setupPrompt)
        }
    }

    struct MacMCPSettingsView: View {
        @EnvironmentObject private var settingsShellViewModel: MacSettingsShellViewModel
        @StateObject private var viewModel = MacMCPSettingsViewModel()

        var body: some View {
            Form {
                Section {
                    Toggle(
                        "MCP Server",
                        isOn: Binding(
                            get: { viewModel.isEnabled },
                            set: { viewModel.setEnabled($0) }
                        )
                    )
                    .disabled(viewModel.isTransitioning)

                    HStack(spacing: 6) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 7, height: 7)
                        Text(statusText)
                            .foregroundStyle(.secondary)
                    }
                    .font(.callout)
                } footer: {
                    Text("Let your coding agent access Stet through MCP.")
                }

                Section("Connect your coding agent") {
                    instructionRow(number: 1, text: "Turn on MCP Server")
                    instructionRow(number: 2, text: "Copy the setup prompt")
                    instructionRow(number: 3, text: "Paste it into your coding agent")

                    Button(viewModel.copySucceeded ? "Copied" : "Copy Setup Prompt") {
                        viewModel.copySetupPrompt()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!viewModel.isEnabled)
                }
            }
            .macSettingsFormStyle()
            .padding(.bottom, MacUI.SettingsViewMetrics.formBottomPadding)
            .task {
                viewModel.configure(appModel: settingsShellViewModel)
            }
        }

        private func instructionRow(number: Int, text: LocalizedStringKey) -> some View {
            HStack(spacing: 10) {
                Text("\(number)")
                    .font(.caption.weight(.semibold))
                    .frame(width: 22, height: 22)
                    .background(MacUI.Surfaces.selection, in: Circle())
                Text(text)
            }
        }

        private var statusText: LocalizedStringKey {
            switch viewModel.state {
            case .disabled:
                "Off"
            case .starting:
                "Starting…"
            case .running:
                "Running"
            case .failed:
                "Failed to start"
            }
        }

        private var statusColor: Color {
            switch viewModel.state {
            case .running:
                .green
            case .failed:
                .red
            case .starting:
                .orange
            case .disabled:
                .secondary
            }
        }
    }
#endif
