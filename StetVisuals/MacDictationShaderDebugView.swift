#if os(macOS)
    import SwiftUI

    @available(macOS 15.0, *)
    public struct MacDictationShaderDebugView: View {
        public init() {}

        public var body: some View {
            MacDictationShaderWorkbenchView()
        }
    }

    #if DEBUG
        #Preview("Shader Debug") {
            if #available(macOS 15.0, *) {
                MacDictationShaderDebugView()
            } else {
                Text("Requires macOS 15 or newer")
                    .padding()
            }
        }
    #endif
#endif
