#if os(macOS)
    import SwiftUI

    struct MacShaderDebugSettingsView: View {
        @Environment(\.openWindow) private var openWindow

        var body: some View {
            LinearPageContainer(title: "Debug") {
                LinearSectionGroup("Shader Debug Window") {
                    LinearSettingRow(
                        "Shader Workbench",
                        subtitle: "Open a large shader workbench window for screenshot capture and color tuning."
                    ) {
                        Button("Open Shader Debug Window") {
                            openWindow(id: MacWindowSceneID.shaderDebug)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
    }
#endif
