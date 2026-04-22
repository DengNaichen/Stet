#if os(macOS)
    import SwiftUI
    import AppKit

    struct MacDictationErrorSurface: View {
        let text: String
        let isInsufficientFunds: Bool
        let layout: MacDictationPanelLayout
        let onTopUp: () -> Void
        let onFinish: () -> Void

        @State private var contentVisible = false

        private var surfaceShape: RoundedRectangle {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
        }

        var body: some View {
            VStack(spacing: 8) {
                Text(text)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .padding(.horizontal, 24)

                HStack(spacing: 12) {
                    if isInsufficientFunds {
                        Button(action: {
                            onTopUp()
                            onFinish()
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "crown.fill")
                                    .font(.system(size: 11, weight: .bold))
                                Text("Upgrade")
                                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .background {
                                Capsule().fill(Color.blue)
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    Button(action: onFinish) {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 11, weight: .bold))
                            Text("Dismiss")
                                .font(.system(size: 11, weight: .heavy, design: .rounded))
                        }
                        .foregroundStyle(.red)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background {
                            Capsule()
                                .fill(Color.red.opacity(0.12))
                                .overlay {
                                    Capsule().stroke(Color.red.opacity(0.2), lineWidth: 0.5)
                                }
                        }
                    }
                    .buttonStyle(.plain)
                }
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
