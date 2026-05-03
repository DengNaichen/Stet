import SwiftUI
import Combine
import KeyboardKit

struct StetKeyboardView: View {
    unowned let controller: KeyboardViewController
    @State private var buttonState: KeyboardButtonState = .idle
    @State private var processingStartDate: Date? = nil

    private var isPending: Bool { buttonState == .pending }
    private var isRecording: Bool { buttonState == .recording }
    private var isProcessing: Bool { buttonState == .processing }
    // isActive drives button color/icon; isRecording drives waveform (only when confirmed recording)
    private var isActive: Bool { isPending || isRecording }

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
        .onReceive(controller.$buttonState) { buttonState = $0 }
        .onReceive(controller.$processingStartDate) { processingStartDate = $0 }
    }

    private var micToolbar: some View {
        HStack {
            Spacer()
            Button(action: toggleRecording) {
                Image(systemName: isActive ? "stop.fill" : "triangle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(isProcessing ? .clear : .white)
                    .frame(width: 60, height: 38)
                    .background(isActive ? Color.red.opacity(isRecording ? 1.0 : 0.65) : Color.black.opacity(0.75))
                    .clipShape(Capsule())
                    .overlay(alignment: .topLeading) {
                        if isRecording {
                            MicWaveform()
                                .padding(.top, 4)
                                .padding(.leading, 6)
                        }
                    }
                    .overlay {
                        if let start = processingStartDate {
                            TimelineView(.animation(minimumInterval: 1.0 / 30)) { ctx in
                                let elapsed = ctx.date.timeIntervalSince(start)
                                let progress = CGFloat(min(0.95, 1.0 - exp(-elapsed * 1.15)))
                                ZStack(alignment: .leading) {
                                    Color.black.opacity(0.75)
                                    Color.white.opacity(0.25)
                                        .frame(width: 60 * progress)
                                    Text("…")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.8))
                                        .frame(maxWidth: .infinity)
                                }
                                .clipShape(Capsule())
                            }
                            .allowsHitTesting(false)
                        }
                    }
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                    )
            }
            .disabled(isProcessing)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in controller.prepareButtonFeedback() }
            )
            .padding(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 10))
        }
    }

    private func toggleRecording() {
        if isRecording {
            controller.handleMicUp()
        } else {
            controller.handleMicDown()
        }
        controller.triggerButtonFeedback()
    }
}

private struct MicWaveform: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 20)) { context in
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
