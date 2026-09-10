import SwiftUI

struct KeyboardView: View {
    var onMicDown: () -> Void
    var onMicUp: () -> Void
    var onBackspace: () -> Void
    var onReturn: () -> Void
    var onNextKeyboard: () -> Void

    @State private var isPressing = false

    var body: some View {
        ZStack {
            VStack(spacing: 20) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(Color(.systemBackground))
                    .frame(width: 112, height: 112)
                    .background(isPressing ? Color(.systemRed) : Color(.label))
                    .clipShape(Circle())
                    .contentShape(Circle())
                    .scaleEffect(isPressing ? 0.97 : 1.0)
                    .animation(.spring(response: 0.25, dampingFraction: 1), value: isPressing)
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

                Button(action: onReturn) {
                    Text("return")
                        .font(.system(size: 16))
                        .foregroundStyle(.primary)
                        .frame(width: 120, height: 52)
                        .background(Color(.systemGray4))
                        .clipShape(Capsule())
                }
            }
            .offset(y: 4)

            KeyboardButton(icon: "delete.left.fill", size: 52, iconSize: 20, action: onBackspace)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .padding(.trailing, 20)

            Button(action: onNextKeyboard) {
                Image(systemName: "globe")
                    .font(.system(size: 28))
                    .foregroundStyle(.primary)
                    .frame(width: 52, height: 52)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(.leading, 20)
            .padding(.bottom, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGray6))
    }

    struct KeyboardButton: View {
        let icon: String
        let size: CGFloat
        let iconSize: CGFloat
        let action: () -> Void

        init(icon: String, size: CGFloat = 44, iconSize: CGFloat = 18, action: @escaping () -> Void) {
            self.icon = icon
            self.size = size
            self.iconSize = iconSize
            self.action = action
        }

        var body: some View {
            Button(action: action) {
                Image(systemName: icon)
                    .font(.system(size: iconSize))
                    .foregroundStyle(Color(.label))
                    .frame(width: size, height: size)
                    .background(Color(.systemGray4))
                    .clipShape(Circle())
            }
        }
    }
}
