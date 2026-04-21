#if os(macOS)
    import SwiftUI

    struct OnboardingModelDownloadStep: View {
        @ObservedObject var viewModel: OnboardingViewModel

        var body: some View {
            VStack(alignment: .leading, spacing: 20) {
                downloadCard

                Spacer()

                Text("Installs to Application Support")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                OnboardingActionButton(
                    title: viewModel.localWhisperDownloadPrimaryButtonTitle,
                    isEnabled: !isRunning,
                    minHeight: 52,
                    isCentered: true
                ) {
                    Task {
                        await viewModel.handleLocalWhisperDownloadPrimaryAction()
                    }
                }
            }
        }

        @ViewBuilder
        private var downloadCard: some View {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    statusIcon
                    Text(statusTitle)
                        .font(.title3.weight(.semibold))
                }

                Text(statusMessage)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
        }

        private var isRunning: Bool {
            if case .running = viewModel.localWhisperDownloadState {
                return true
            }

            return false
        }

        @ViewBuilder
        private var statusIcon: some View {
            switch viewModel.localWhisperDownloadState {
            case .idle:
                Image(systemName: "square.and.arrow.down.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.blue)
            case .running:
                ProgressView()
                    .controlSize(.small)
            case .ready:
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.green)
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }

        private var statusTitle: String {
            switch viewModel.localWhisperDownloadState {
            case .idle:
                return "Download the local model"
            case .running:
                return "Preparing Local Whisper"
            case .ready:
                return "Local Whisper is ready"
            case .failed:
                return "Download failed"
            }
        }

        private var statusMessage: String {
            switch viewModel.localWhisperDownloadState {
            case .idle:
                return "Download the default Whisper model to this Mac before continuing."
            case .running:
                return viewModel.localWhisperDownloadDetailText
            case .ready:
                return "The default model has been installed."
            case .failed(let message):
                return message
            }
        }
    }

    #if DEBUG
        #Preview {
            OnboardingModelDownloadStep(
                viewModel: OnboardingViewModel(coordinator: MockOnboardingCoordinator(step: .download))
            )
            .frame(width: 440)
            .padding()
        }
    #endif

#endif
