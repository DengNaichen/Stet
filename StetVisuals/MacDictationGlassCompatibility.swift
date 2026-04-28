#if os(macOS)
    import SwiftUI

    /// A compatibility wrapper for the macOS 26+ Liquid Glass effect.
    /// On older versions, it falls back to a standard material background.
    public struct MacDictationGlassContainer<Content: View>: View {
        public let spacing: CGFloat
        @ViewBuilder public let content: () -> Content

        public init(spacing: CGFloat, @ViewBuilder content: @escaping () -> Content) {
            self.spacing = spacing
            self.content = content
        }

        public var body: some View {
            if #available(macOS 26.0, *) {
                GlassEffectContainer(spacing: spacing, content: content)
            } else {
                HStack(spacing: spacing) {
                    content()
                }
            }
        }
    }

    extension View {
        @ViewBuilder
        public func stetGlassEffect<S: Shape>(in shape: S) -> some View {
            if #available(macOS 26.0, *) {
                self.glassEffect(in: shape)
            } else {
                self.background(.ultraThinMaterial)
                    .clipShape(shape)
            }
        }

        @ViewBuilder
        public func stetGlassEffect() -> some View {
            if #available(macOS 26.0, *) {
                self.glassEffect(.regular.tint(nil))
            } else {
                self.background(.ultraThinMaterial)
                    .clipShape(Capsule())
            }
        }

        @ViewBuilder
        public func stetGlassID(_ id: String, in namespace: Namespace.ID) -> some View {
            if #available(macOS 26.0, *) {
                self.glassEffectID(id, in: namespace)
            } else {
                self
            }
        }
    }
#endif
