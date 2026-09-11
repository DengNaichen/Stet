#if os(macOS)
    import SwiftUI

    public struct MacDictationCapsuleVisualView: View {
        let model: MacDictationCapsuleVisualModel
        let actions: MacDictationCapsuleVisualActions

        public init(model: MacDictationCapsuleVisualModel, actions: MacDictationCapsuleVisualActions) {
            self.model = model
            self.actions = actions
        }

        public var body: some View {
            MacWatercolorOrbView(model: model, actions: actions)
        }
    }
#endif
