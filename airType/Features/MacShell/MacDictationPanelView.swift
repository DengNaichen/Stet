#if os(macOS)
import SwiftUI

struct MacDictationPanelView: View {
    @EnvironmentObject private var appModel: MacAppModel

    private let capsuleWidth: CGFloat = 340

    var body: some View {
        Group {
            switch appModel.dictationViewModel.state {
            case .idle:
                idleCapsule
            case .listening:
                recordingCapsule
            case .processing:
                thinkingCapsule
            case .result:
                insertedCapsule
            case .error(let message):
                errorCapsule(message: message)
            }
        }
        .frame(width: capsuleWidth)
        .padding(12)
    }

    private var idleCapsule: some View {
        shell {
            HStack(spacing: 12) {
                controlButton(
                    systemName: "xmark",
                    isEmphasized: false,
                    action: appModel.hidePanel
                )

                VStack(spacing: 3) {
                    Text("Ready")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity)

                controlButton(
                    systemName: "mic.fill",
                    isEmphasized: true,
                    action: appModel.performPrimaryAction
                )
            }
        }
    }

    private var recordingCapsule: some View {
        shell {
            HStack(spacing: 14) {
                controlButton(
                    systemName: "xmark",
                    isEmphasized: false,
                    action: appModel.cancelActiveCapture
                )

                VoiceLevelBarsView(level: appModel.recordingLevel)
                    .frame(maxWidth: .infinity)

                controlButton(
                    systemName: "checkmark",
                    isEmphasized: true,
                    action: appModel.performPrimaryAction
                )
            }
        }
    }

    private var thinkingCapsule: some View {
        shell {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)

                Text(appModel.statusText)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
    }

    private var insertedCapsule: some View {
        shell {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.white)

                Text(appModel.statusText)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
    }

    private func errorCapsule(message: String) -> some View {
        shell {
            HStack(spacing: 12) {
                controlButton(
                    systemName: "xmark",
                    isEmphasized: false,
                    action: appModel.hidePanel
                )

                Text(message)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.84))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                controlButton(
                    systemName: "arrow.clockwise",
                    isEmphasized: true,
                    action: appModel.performPrimaryAction
                )
            }
        }
    }

    private func shell<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.black.opacity(0.92))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.28), radius: 20, y: 14)
    }

    private func controlButton(
        systemName: String,
        isEmphasized: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(isEmphasized ? .black : .white)
                .frame(width: 46, height: 46)
                .background(
                    Circle()
                        .fill(isEmphasized ? Color.white : Color.white.opacity(0.12))
                )
        }
        .buttonStyle(.plain)
    }
}

private struct VoiceLevelBarsView: View {
    let level: Double

    private let multipliers: [CGFloat] = [0.35, 0.5, 0.72, 0.9, 1, 0.9, 0.72, 0.5, 0.35]

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            ForEach(Array(multipliers.enumerated()), id: \.offset) { _, multiplier in
                Capsule()
                    .fill(Color.white)
                    .frame(width: 4, height: barHeight(multiplier: multiplier))
            }
        }
        .frame(height: 28)
        .animation(.spring(response: 0.18, dampingFraction: 0.72), value: level)
    }

    private func barHeight(multiplier: CGFloat) -> CGFloat {
        let baseHeight: CGFloat = 5
        let variableHeight = CGFloat(max(level, 0.08)) * 18 * multiplier
        return baseHeight + variableHeight
    }
}
#endif
