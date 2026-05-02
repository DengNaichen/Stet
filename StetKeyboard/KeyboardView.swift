import SwiftUI
import Combine
import KeyboardKit

struct StetKeyboardView: View {
    unowned let controller: KeyboardViewController
    @State private var sessionState: DictationState = .idle
    @State private var pulse = false

    private let sessionPoll = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    private var isPending: Bool {
        sessionState == .requestStart || sessionState == .launching || sessionState == .warming
    }
    private var isRecording: Bool { sessionState == .recording }
    private var isProcessing: Bool { sessionState == .transcribing }
    // isActive drives button color/icon; isRecording drives waveform (only when confirmed recording)
    private var isActive: Bool { isPending || isRecording }
    private var isSpeaking: Bool { sessionState == .recording || sessionState == .transcribing }

    private var customLayout: KeyboardLayout {
        var layout = KeyboardLayout.standard(for: controller.state.keyboardContext)
        for i in 0..<layout.itemRows.count {
            for j in 0..<layout.itemRows[i].count {
                if layout.itemRows[i][j].action.isAlphabeticKeyboardTypeAction {
                    layout.itemRows[i][j].action = .nextKeyboard
                    layout.itemRows[i][j].size.width = .points(60)
                } else if layout.itemRows[i][j].action == .nextKeyboard {
                    layout.itemRows[i][j].size.width = .points(60)
                }
            }
        }
        return layout
    }

    var body: some View {
        KeyboardView(
            layout: customLayout,
            services: controller.services,
            buttonContent: { params in
                if params.item.action == .nextKeyboard {
                    Text("ABC")
                        .font(.system(size: 15, weight: .medium))
                } else {
                    params.view
                }
            },
            buttonView: { $0.view },
            collapsedView: { $0.view },
            emojiKeyboard: { $0.view },
            toolbar: { _ in micToolbar }
        )
        .keyboardViewBackground(.hidden)
        .keyboardViewStyle(KeyboardViewStyle(edgeInsets: EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8)))
        .onReceive(sessionPoll) { _ in
            sessionState = SharedDictationManager.shared.getSession()?.state ?? .idle
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
                Image(systemName: isActive ? "stop.fill" : "triangle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.white)
                    .frame(width: 60, height: 38)
                    .background(isActive ? Color.red.opacity(isRecording ? 1.0 : 0.65) : Color.black.opacity(0.75))
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
        if isRecording {
            controller.handleMicUp()
        } else {
            controller.handleMicDown()
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

