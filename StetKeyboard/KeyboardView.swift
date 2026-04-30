import SwiftUI

struct KeyboardView: View {
    var onMicTap: () -> Void
    var onKeyTap: (String) -> Void
    var onBackspace: () -> Void
    var onReturn: () -> Void
    var onNextKeyboard: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                KeyboardButton(icon: "at", action: { onKeyTap("@") })
                KeyboardButton(icon: "minus", action: { onKeyTap("_") })

                Button(action: onMicTap) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 132, height: 58)
                        .background(Color.black)
                        .clipShape(Capsule())
                }

                KeyboardButton(icon: "delete.left", action: onBackspace)
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
