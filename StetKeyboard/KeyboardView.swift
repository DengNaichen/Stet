import SwiftUI

struct KeyboardView: View {
    var onMicDown: () -> Void
    var onMicUp: () -> Void
    var onKeyTap: (String) -> Void
    var onBackspace: () -> Void
    var onReturn: () -> Void
    var onNextKeyboard: () -> Void

    @State private var isPressing = false

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                KeyboardButton(icon: "at", action: { onKeyTap("@") })
                KeyboardButton(icon: "minus", action: { onKeyTap("_") })

                Image(systemName: "mic.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 132, height: 58)
                    .background(isPressing ? Color.red : Color.black)
                    .clipShape(Capsule())
                    .scaleEffect(isPressing ? 1.1 : 1.0)
                    .animation(.spring(), value: isPressing)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in
                                if !isPressing {
                                    isPressing = true
                                    onMicDown()
                                }
                            }
                            .onEnded { _ in
                                isPressing = false
                                onMicUp()
                            }
                    )

                KeyboardButton(icon: "delete.left", action: onBackspace)
            }

            HStack(spacing: 12) {
                Button(action: {
                    // This will trigger the completion logic in controller
                    onKeyTap("__DONE__") 
                }) {
                    Text("DONE")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Color.blue)
                        .clipShape(Capsule())
                }
            }

            HStack(spacing: 12) {
                Button(action: onNextKeyboard) {
                    Image(systemName: "globe")
                        .font(.title2)
                        .foregroundColor(.primary)
                        .frame(width: 52, height: 44)
                        .background(Color(.systemGray4))
                        .clipShape(Capsule())
                }

                Button(action: { onKeyTap(" ") }) {
                    Text("space")
                        .font(.body)
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Color(.systemGray5))
                        .clipShape(Capsule())
                }

                Button(action: onReturn) {
                    Text("return")
                        .font(.body)
                        .foregroundColor(.primary)
                        .frame(width: 86, height: 44)
                        .background(Color(.systemGray4))
                        .clipShape(Capsule())
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGray6))
    }
}

private struct KeyboardButton: View {
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.primary)
                .frame(width: 48, height: 48)
                .background(Color(.systemGray4))
                .clipShape(Circle())
        }
    }
}
