#if os(macOS)
    import SwiftUI

    struct MacShaderDebugSettingsView: View {
        @Environment(\.openWindow) private var openWindow

        var body: some View {
            VStack(alignment: .leading, spacing: MacUI.SettingsViewMetrics.cardContentSpacing) {
                GroupBox {
                    VStack(alignment: .leading, spacing: MacUI.SettingsViewMetrics.controlSpacing) {
                        Text("Shader Debug Window")
                            .font(MacUI.Typography.heading)

                        Text(
                            "Open a large shader workbench window for screenshot capture and color tuning."
                        )
                        .foregroundStyle(MacUI.Foreground.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    openWindow(id: MacWindowSceneID.shaderDebug)
                } label: {
                    Text("Open Shader Debug Window")
                        .frame(minWidth: MacUI.SettingsViewMetrics.prominentActionMinimumWidth)
                }
                .buttonStyle(.borderedProminent)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(MacUI.SettingsViewMetrics.standaloneContentPadding)
        }
    }
#endif
