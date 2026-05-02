import SwiftUI
import Combine
import KeyboardKit

struct StetKeyboardView: View {
    unowned let controller: KeyboardViewController
    @State private var isRecording = false  // optimistic local state, resets when session ends
    @State private var sessionState: DictationState = .idle
    @State private var pulse = false

    private let sessionPoll = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    private var isProcessing: Bool { sessionState == .transcribing }
    private var isSpeaking: Bool { isRecording || sessionState == .recording || sessionState == .transcribing }

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
        .stetGlassBackground()
        .clipShape(
            UnevenRoundedRectangle(
                cornerRadii: .init(topLeading: 16, bottomLeading: 0, bottomTrailing: 0, topTrailing: 16)
            )
        )
        .onReceive(sessionPoll) { _ in
            sessionState = SharedDictationManager.shared.getSession()?.state ?? .idle
            if sessionState == .idle || sessionState == .ready || sessionState == .inserted {
                isRecording = false
            }
        }
        .onChange(of: isProcessing) { _, processing in
            if processing {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            } else {
                withAnimation(.easeInOut(duration: 0.2)) { pulse = false }
            }
        }
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
                    .overlay(alignment: .topLeading) {
                        if isSpeaking {
                            MicWaveform()
                                .padding(.top, 4)
                                .padding(.leading, 6)
                        }
                    }
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                    )
                    .overlay {
                        if isProcessing {
                            Capsule()
                                .stroke(Color.white.opacity(0.55), lineWidth: 2)
                                .blur(radius: 4)
                                .scaleEffect(pulse ? 1.12 : 1.0)
                                .opacity(pulse ? 0.0 : 0.6)
                        }
                    }
            }
            .padding(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 10))
        }
    }

    private func toggleRecording() {
        if isRecording || sessionState == .recording {
            controller.handleMicUp()
            isRecording = false
        } else {
            controller.handleMicDown()
            isRecording = true
        }
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
    }
}

private struct MicWaveform: View {
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 1.5) {
                ForEach(0..<3, id: \.self) { i in
                    Capsule()
                        .fill(Color.white.opacity(0.85))
                        .frame(width: 2, height: barHeight(for: i, t: t))
                }
            }
            .frame(width: 14, height: 10, alignment: .center)
        }
    }

    private func barHeight(for i: Int, t: Double) -> CGFloat {
        let phase = t * 6 + Double(i) * 1.2
        let v = (sin(phase) + 1) / 2
        return 3 + CGFloat(v) * 6
    }
}

private struct StetGlassBackground: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(tint)
            .background(.ultraThickMaterial)
    }

    private var tint: Color {
        // iOS 26 .glassEffect always renders a specular rim that cannot be
        // suppressed; use .ultraThickMaterial + a tint to control depth instead.
        switch colorScheme {
        case .dark:  return Color.black.opacity(0.30)
        case .light: return Color.black.opacity(0.05)
        @unknown default: return Color.black.opacity(0.05)
        }
    }
}

private extension View {
    func stetGlassBackground() -> some View {
        modifier(StetGlassBackground())
    }
}
