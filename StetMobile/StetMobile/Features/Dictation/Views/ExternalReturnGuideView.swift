import SwiftUI

struct ExternalReturnGuideView: View {
    let onDismiss: () -> Void
    @State private var animateSwipeHint = false

    var body: some View {
        VStack(spacing: 32) {
            HStack {
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                        .background(Color(.tertiarySystemFill), in: Circle())
                }
                .accessibilityLabel("Close")
            }
            .padding(.top, 12)
            .padding(.horizontal, 20)

            Spacer()

            VStack(spacing: 12) {
                Label("Transcript Ready", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(.green.opacity(0.12), in: Capsule())

                Text("Swipe back to your app")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .multilineTextAlignment(.center)

                Text("Your text will be inserted automatically when you return.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 42, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .frame(width: 224, height: 244)
                    .overlay(
                        RoundedRectangle(cornerRadius: 42, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.18), lineWidth: 5)
                    )
                    .shadow(color: .black.opacity(0.08), radius: 20, y: 10)

                VStack(spacing: 18) {
                    HStack(spacing: 5) {
                        ForEach(0..<6, id: \.self) { index in
                            Capsule()
                                .fill(Color.primary.opacity(0.75))
                                .frame(width: 5, height: CGFloat([18, 36, 26, 44, 22, 32][index]))
                        }
                    }

                    VStack(spacing: 4) {
                        Text("Apple Speech")
                            .font(.caption.weight(.semibold))
                        Text("iPhone Microphone Ready")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 8)

            Spacer()

            VStack(spacing: 14) {
                Text("Swipe right along the bottom bar")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.15))
                        .frame(width: 144, height: 6)

                    Capsule()
                        .fill(Color.primary)
                        .frame(width: 54, height: 6)
                        .offset(x: animateSwipeHint ? 90 : 0)
                }
                .animation(
                    .easeInOut(duration: 1.4).repeatForever(autoreverses: true),
                    value: animateSwipeHint
                )
            }
            .padding(.bottom, 36)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .onAppear {
            animateSwipeHint = true
        }
    }
}

#Preview {
    ExternalReturnGuideView(onDismiss: {})
}
