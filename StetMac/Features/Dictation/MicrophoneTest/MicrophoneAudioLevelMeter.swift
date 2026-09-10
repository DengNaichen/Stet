import SwiftUI

/// A quiet, continuous input meter that stays empty when the microphone is silent.
struct MicrophoneAudioLevelMeter: View {
    let level: Double

    private var normalizedLevel: Double { level.isFinite ? min(1, max(0, level)) : 0 }

    var body: some View {
        GeometryReader { geometry in
            Capsule()
                .fill(MacUI.Surfaces.selection)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(MacUI.Surfaces.ink.opacity(0.7))
                        .frame(width: geometry.size.width * normalizedLevel)
                }
        }
        .frame(height: 5)
        .animation(.easeOut(duration: 0.1), value: normalizedLevel)
        .accessibilityLabel("Microphone input level")
        .accessibilityValue("\(Int(normalizedLevel * 100)) percent")
    }
}
