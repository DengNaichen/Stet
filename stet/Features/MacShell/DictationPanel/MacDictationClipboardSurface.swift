#if os(macOS)
    import SwiftUI

    struct MacDictationClipboardSurface: View {
        let text: String
        let layout: MacDictationPanelLayout
        let onFinish: () -> Void

        @State private var contentVisible = false

        private var surfaceShape: RoundedRectangle {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
        }

        var body: some View {
            VStack(spacing: 8) {
                Text(text)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.96))
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .padding(.horizontal, 24)

                Button(action: onFinish) {
                    HStack(spacing: 6) {
                        Image(systemName: "scissors")
                            .font(.system(size: 11, weight: .bold))
                        Text("OK")
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background {
                        Capsule()
                            .fill(.white.opacity(0.12))
                            .overlay {
                                Capsule().stroke(.white.opacity(0.1), lineWidth: 0.5)
                            }
                    }
                }
                .buttonStyle(.plain)
            }
            .frame(width: layout.panelSize.width, height: layout.panelSize.height, alignment: .center)
            .glassEffect(in: surfaceShape)
            .opacity(contentVisible ? 1 : 0)
            .offset(y: contentVisible ? 0 : 8)
            .scaleEffect(contentVisible ? 1 : 0.985)
            .onAppear {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9).delay(0.09)) {
                    contentVisible = true
                }
            }
        }
    }
#endif
