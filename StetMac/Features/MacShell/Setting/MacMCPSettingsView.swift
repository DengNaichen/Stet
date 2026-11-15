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
            LinearPageContainer(title: "MCP") {
                LinearSectionGroup(
                    "MCP Server",
                    footer: "Let your coding agent access Stet through MCP."
                ) {
                    LinearSettingRow(
                        "MCP Server",
                        subtitle: "Local HTTP endpoint at http://127.0.0.1:49321/mcp"
                    ) {
                        Toggle(
                            "",
                            isOn: Binding(
                                get: { viewModel.isEnabled },
                                set: { viewModel.setEnabled($0) }
                            )
                        )
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .tint(MacUI.LinearBrand.accent)
                        .disabled(viewModel.isTransitioning)
                    }

                    LinearSettingRow("Server Status") {
                        LinearBadge(text: statusTitle, tint: statusColor, showDot: true)
                    }
                }

                LinearSectionGroup("Connect your coding agent") {
                    instructionRow(number: 1, text: "Turn on MCP Server")
                    instructionRow(number: 2, text: "Copy the setup prompt")
                    instructionRow(number: 3, text: "Paste it into your coding agent")

                    LinearSettingRow("Setup Prompt") {
                        let copyButtonTitle: LocalizedStringKey =
                            viewModel.copySucceeded ? "Copied" : "Copy Setup Prompt"
                        Button(copyButtonTitle) {
                            viewModel.copySetupPrompt()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!viewModel.isEnabled)
                    }
                }

                LinearSectionGroup("Calendar Tools") {
                    Text("Connected agents can read and modify calendars selected in Meetings settings.")
                        .font(MacUI.LinearTypography.rowSubtitle)
                        .foregroundStyle(MacUI.Foreground.secondary)
                        .padding(.horizontal, MacUI.LinearMetrics.rowHorizontalPadding)
                        .padding(.vertical, 12)
                }
            }
            .task {
                viewModel.configure(appModel: settingsShellViewModel)
            }
        }

        private func instructionRow(number: Int, text: LocalizedStringKey) -> some View {
            HStack(spacing: 10) {
                Text("\(number)")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(MacUI.Foreground.secondary)
                    .frame(width: 20, height: 20)
                    .background(MacUI.LinearSurfaces.elevated, in: Circle())
                    .overlay(Circle().strokeBorder(MacUI.LinearSurfaces.hairlineStrong, lineWidth: 1))
                Text(text)
                    .font(MacUI.LinearTypography.rowTitle)
                    .foregroundStyle(MacUI.Foreground.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, MacUI.LinearMetrics.rowHorizontalPadding)
            .padding(.vertical, 9)
        }

        private var statusTitle: LocalizedStringKey {
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
                MacUI.Foreground.success
            case .failed:
                MacUI.Foreground.error
            case .starting:
                MacUI.Foreground.secondaryColor
            case .disabled:
                MacUI.Foreground.secondaryColor
            }
        }
    }
#endif
