#if os(macOS)
    import SwiftUI

    struct MacShaderDebugSettingsView: View {
        @Environment(\.openWindow) private var openWindow

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Shader Debug Window")
                            .font(.headline)

                        Text(
                            "Open a large shader workbench window for screenshot capture and color tuning."
                        )
                        .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    openWindow(id: MacWindowSceneID.shaderDebug)
                } label: {
                    Text("Open Shader Debug Window")
                        .frame(minWidth: 220)
                }
                .buttonStyle(.borderedProminent)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(20)
        }
    }
#endif
