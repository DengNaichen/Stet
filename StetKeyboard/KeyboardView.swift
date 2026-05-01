import SwiftUI
import KeyboardKit

struct StetKeyboardView: View {
    unowned let controller: KeyboardViewController
    @State private var isRecording = false

    var body: some View {
        KeyboardView(
            layout: .standard(for: controller.state.keyboardContext),
            services: controller.services,
            buttonContent: { $0.view },
            buttonView: { $0.view },
            collapsedView: { $0.view },
            emojiKeyboard: { $0.view },
            toolbar: { _ in micToolbar }
        )
        .background(Color(.systemGray5))
    }

    private var micToolbar: some View {
        HStack {
            Spacer()
            Button(action: toggleRecording) {
                Image(systemName: isRecording ? "stop.fill" : "triangle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.white)
                    .frame(width: 60, height: 38)
                    .background(isRecording ? Color.red : Color.black.opacity(0.75))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                    )
            }
            .padding(.trailing, 10)
        }
    }

    private func toggleRecording() {
        if isRecording {
            controller.handleMicUp()
        } else {
            controller.handleMicDown()
        }
        isRecording.toggle()

        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
    }
}
