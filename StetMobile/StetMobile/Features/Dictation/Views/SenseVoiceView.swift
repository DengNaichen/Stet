import SwiftUI
import UIKit

struct SenseVoiceView: View {
    @ObservedObject var viewModel: SenseVoiceViewModel
    @ObservedObject private var timingStore = DictationTimingStore.shared
    var languageLabel: String?
    var speechAssetStatus: AppleSpeechAssetStatus = .installed
    var isRewriteEnabled: Bool = false
    var onOpenSettings: (() -> Void)?

    @AppStorage(
        MobileDictationVisualTheme.mobileStorageKey,
        store: MobileDictationVisualTheme.mobileDefaults
    ) private var themeRawValue = MobileDictationVisualTheme.egg.rawValue

    @State private var didCopyTranscript = false
    @State private var copyResetTask: Task<Void, Never>?
    @State private var isShowingTimingHistory = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                headerRow
                    .padding(.top, 8)

                statusHeaderBar

                transcriptCard

                if let latestTiming = timingStore.latest {
                    timingBreakdownStrip(latestTiming)
                }

                recordingDock
                    .padding(.bottom, 12)
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .sheet(isPresented: $isShowingTimingHistory) {
                DictationTimingHistorySheet(timingStore: timingStore)
            }
            .toolbar(.hidden, for: .navigationBar)
            .onDisappear {
                copyResetTask?.cancel()
            }
        }
    }

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Dictation")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.primary)

            Spacer(minLength: 8)

            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    if let languageLabel {
                        Button {
                            onOpenSettings?()
                        } label: {
                            HStack(spacing: 4) {
                                Text(languageLabel)
                                    .font(.subheadline.weight(.medium))
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .frame(height: 36)
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.interactive(), in: .capsule)
                        .accessibilityLabel("Recognition language \(languageLabel)")
                    }

                    Menu {
                        ForEach(MobileDictationVisualTheme.allCases) { theme in
                            Button {
                                themeRawValue = theme.rawValue
                            } label: {
                                if theme == selectedTheme {
                                    Label(theme.title, systemImage: "checkmark")
                                } else {
                                    Text(theme.title)
                                }
                            }
                        }
                    } label: {
                        ThemeOrbSwatch(theme: selectedTheme, size: 24)
                            .frame(width: 36, height: 36)
                            .contentShape(Circle())
                    }
                    .glassEffect(.regular.interactive(), in: .circle)
                    .accessibilityLabel("Voice orb theme")
                }
            }
        }
        .frame(minHeight: 40)
    }

    private var statusHeaderBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusDotColor)
                .frame(width: 8, height: 8)
                .shadow(color: statusDotColor.opacity(0.45), radius: 4)

            Text(statusHeadline)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(statusColor)
                .lineLimit(1)

            Spacer(minLength: 8)

            if isRewriteEnabled {
                Label("AI Polish", systemImage: "sparkles")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color(.tertiarySystemFill), in: Capsule())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: Capsule()
        )
        .overlay(
            Capsule()
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }

    private var transcriptCard: some View {
        VStack(spacing: 0) {
            if viewModel.transcript.isEmpty {
                emptyTranscriptBody
            } else {
                ScrollView {
                    Text(viewModel.transcript)
                        .font(.system(.title3, design: .default).weight(.regular))
                        .lineSpacing(6)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(22)
                }
                .scrollBounceBehavior(.basedOnSize)

                Divider()
                    .opacity(0.5)

                HStack(spacing: 12) {
                    if viewModel.state == .rewriting {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.mini)
                            Text("Polishing…")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    } else if viewModel.state == .recording {
                        HStack(spacing: 6) {
                            Image(systemName: "waveform")
                                .symbolEffect(.variableColor.iterative, isActive: true)
                                .font(.caption)
                                .foregroundStyle(selectedTheme.accentColor)
                            Text("Listening live")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("\(viewModel.transcript.count) chars")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    Button {
                        copyTranscript()
                    } label: {
                        Label(
                            didCopyTranscript ? "Copied" : "Copy",
                            systemImage: didCopyTranscript ? "checkmark" : "doc.on.doc"
                        )
                        .font(.subheadline.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .tint(didCopyTranscript ? .green : .primary)

                    Button(role: .destructive) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 1.0)) {
                            viewModel.clearTranscript()
                        }
                    } label: {
                        Image(systemName: "trash")
                            .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .accessibilityLabel("Clear transcript")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.75)
        )
        .shadow(color: .black.opacity(0.04), radius: 14, y: 6)
    }

    private var emptyTranscriptBody: some View {
        VStack(spacing: 16) {
            Spacer()

            if case .failed = viewModel.state {
                Image(systemName: "mic.slash.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.red.opacity(0.85))

                VStack(spacing: 6) {
                    Text("Dictation Unavailable")
                        .font(.headline)
                    Text(emptyStateGuidance)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                HStack(spacing: 12) {
                    Button("Retry") {
                        viewModel.ensureMicAlive()
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.regular)

                    if !speechAssetStatus.isInstalled, let onOpenSettings {
                        Button("Speech Settings") {
                            onOpenSettings()
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .controlSize(.regular)
                    }
                }
                .padding(.top, 4)
            } else {
                Image(systemName: "waveform.and.mic")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(.tertiary)
                    .padding(18)
                    .background(Color(.tertiarySystemFill), in: Circle())

                VStack(spacing: 6) {
                    Text(emptyHeadlineText)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(emptySubtitleText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                if case .available = speechAssetStatus, let onOpenSettings {
                    Button {
                        onOpenSettings()
                    } label: {
                        Label("Download On-Device Speech Model", systemImage: "arrow.down.circle")
                            .font(.subheadline.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .padding(.top, 4)
                }
            }

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var recordingDock: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(selectedTheme.accentColor.opacity(usesListeningShader ? 0.20 : 0.08))
                    .frame(width: usesListeningShader ? 138 : 124, height: usesListeningShader ? 138 : 124)
                    .blur(radius: usesListeningShader ? 18 : 10)
                    .animation(.spring(response: 0.4, dampingFraction: 1.0), value: usesListeningShader)

                if usesListeningShader {
                    DictationLevelShaderView(
                        level: viewModel.recordingLevel,
                        diameter: 112,
                        preferredFramesPerSecond: 40,
                        isPaused: isListeningShaderPaused,
                        theme: selectedTheme
                    )
                    .shadow(color: selectedTheme.accentColor.opacity(0.28), radius: 18, y: 6)
                    .overlay {
                        if viewModel.state == .recording {
                            Button(action: viewModel.toggleRecording) {
                                ZStack {
                                    Color.clear
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(.white.opacity(0.92))
                                        .frame(width: 24, height: 24)
                                        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                                }
                                .frame(width: 112, height: 112)
                                .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Stop Recording")
                        } else {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(1.15)
                        }
                    }
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
                } else {
                    Button {
                        if case .failed = viewModel.state {
                            viewModel.ensureMicAlive()
                        } else {
                            viewModel.toggleRecording()
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(idleButtonBackground)
                                .frame(width: 112, height: 112)
                                .shadow(color: .black.opacity(0.16), radius: 16, y: 6)

                            if viewModel.state == .loading || viewModel.state == .starting {
                                ProgressView()
                                    .tint(Color(.systemBackground))
                                    .scaleEffect(1.2)
                            } else if case .failed = viewModel.state {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 30, weight: .semibold))
                                    .foregroundStyle(.white)
                            } else {
                                Image(systemName: "mic.fill")
                                    .font(.system(size: 32, weight: .medium))
                                    .foregroundStyle(Color(.systemBackground))
                            }
                        }
                    }
                    .buttonStyle(OrbPressButtonStyle())
                    .disabled(!viewModel.canToggleRecording && !isFailedState)
                    .accessibilityLabel(isFailedState ? "Retry Dictation Setup" : "Start Recording")
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
                }
            }
            .frame(height: 138)
            .animation(.spring(response: 0.35, dampingFraction: 1.0), value: usesListeningShader)

            Text(dockHintText)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private func copyTranscript() {
        UIPasteboard.general.string = viewModel.transcript
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.spring(response: 0.25, dampingFraction: 1.0)) {
            didCopyTranscript = true
        }
        copyResetTask?.cancel()
        copyResetTask = Task {
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.25, dampingFraction: 1.0)) {
                didCopyTranscript = false
            }
        }
    }

    private var isFailedState: Bool {
        if case .failed = viewModel.state {
            return true
        }
        return false
    }

    private var idleButtonBackground: Color {
        if isFailedState {
            return .red
        }
        return viewModel.canToggleRecording ? Color.primary : Color(.systemGray3)
    }

    private var usesListeningShader: Bool {
        switch viewModel.state {
        case .recording, .processing, .rewriting:
            true
        case .loading, .idle, .standby, .starting, .failed:
            false
        }
    }

    private var isListeningShaderPaused: Bool {
        switch viewModel.state {
        case .processing, .rewriting:
            true
        case .loading, .idle, .standby, .starting, .recording, .failed:
            false
        }
    }

    private var emptyHeadlineText: String {
        switch viewModel.state {
        case .recording:
            "Listening…"
        case .standby:
            "Mic Paused"
        default:
            "Ready to Dictate"
        }
    }

    private var emptySubtitleText: String {
        if viewModel.state == .standby {
            return
                "Microphone standby timed out to save battery. Tap the orb below or dictate from the Stet keyboard to wake."
        }
        return "Tap the orb below to test here, or switch to the Stet keyboard in any app."
    }

    private var statusHeadline: String {
        switch viewModel.state {
        case .loading:
            return "Preparing Apple Speech…"
        case .idle:
            return "On-Device Ready · Mic Standby"
        case .standby:
            return "Mic Paused · Tap to Wake"
        case .starting:
            return "Starting Microphone…"
        case .recording:
            return "Listening On-Device…"
        case .processing:
            return "Finalizing Transcript…"
        case .rewriting:
            return "Polishing with AI…"
        case .failed:
            return "Setup Attention Needed"
        }
    }

    private var emptyStateGuidance: String {
        if !speechAssetStatus.isInstalled {
            return "Download the on-device speech model in Settings, or tap Retry after granting microphone access."
        }
        return "Check microphone permission in iOS Settings and tap Retry."
    }

    private var dockHintText: String {
        switch viewModel.state {
        case .loading:
            return "Warming up audio session…"
        case .idle:
            return "Tap to speak"
        case .standby:
            return "Tap to wake & speak"
        case .starting:
            return "Opening microphone…"
        case .recording:
            return "Tap orb to stop"
        case .processing:
            return "Finishing on-device speech…"
        case .rewriting:
            return "Applying cloud rewrite…"
        case .failed:
            return "Tap to retry"
        }
    }

    private var statusDotColor: Color {
        switch viewModel.state {
        case .idle:
            return .green
        case .standby:
            return Color(.systemGray)
        case .loading, .starting:
            return .orange
        case .recording:
            return .red
        case .processing, .rewriting:
            return .indigo
        case .failed:
            return .red
        }
    }

    private var statusColor: Color {
        isFailedState ? .red : .primary
    }

    private func timingBreakdownStrip(_ record: DictationTimingRecord) -> some View {
        let localMs = max(0, record.localFinalizeMs)
        let rewriteMs = max(0, record.rewriteMs ?? 0)
        let waitTotal = max(1, localMs + rewriteMs)
        let localRatio = CGFloat(localMs) / CGFloat(waitTotal)

        return Button {
            isShowingTimingHistory = true
        } label: {
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    timingMetric(
                        label: "Start",
                        value: DictationTimingRecord.formatDuration(ms: record.startMs),
                        dotColor: .orange
                    )
                    timingMetric(
                        label: "Local",
                        value: DictationTimingRecord.formatDuration(ms: record.localFinalizeMs),
                        dotColor: .blue
                    )
                    timingMetric(
                        label: "Cloud",
                        value: record.rewriteMs.map { DictationTimingRecord.formatDuration(ms: $0) } ?? "Off",
                        dotColor: .purple
                    )
                    Spacer(minLength: 4)
                    Text("Wait \(DictationTimingRecord.formatDuration(ms: record.totalWaitMs))")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.primary)
                }

                GeometryReader { proxy in
                    HStack(spacing: 2) {
                        Capsule()
                            .fill(Color.blue.gradient)
                            .frame(width: max(4, proxy.size.width * localRatio))
                        if rewriteMs > 0 {
                            Capsule()
                                .fill(Color.purple.gradient)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .frame(height: 5)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Inspect dictation latency breakdown")
    }

    private func timingMetric(label: String, value: String, dotColor: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(dotColor)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospacedDigit().weight(.medium))
                .foregroundStyle(.primary)
        }
    }

    private var selectedTheme: MobileDictationVisualTheme {
        MobileDictationVisualTheme(rawValue: themeRawValue) ?? .egg
    }
}

private struct DictationTimingHistorySheet: View {
    @ObservedObject var timingStore: DictationTimingStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(timingStore.recent) { record in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(record.recordedAt, style: .time)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            if let audioMs = record.audioDurationMs {
                                Text("· Audio \(DictationTimingRecord.formatDuration(ms: audioMs))")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("Total Wait \(DictationTimingRecord.formatDuration(ms: record.totalWaitMs))")
                                .font(.subheadline.monospacedDigit().weight(.semibold))
                        }

                        HStack(spacing: 14) {
                            Label(
                                "Start \(DictationTimingRecord.formatDuration(ms: record.startMs))",
                                systemImage: "play.fill"
                            )
                            .foregroundStyle(.orange)

                            Label(
                                "Local \(DictationTimingRecord.formatDuration(ms: record.localFinalizeMs))",
                                systemImage: "waveform"
                            )
                            .foregroundStyle(.blue)

                            Label(
                                "Cloud \(record.rewriteMs.map { DictationTimingRecord.formatDuration(ms: $0) } ?? "Off")",
                                systemImage: "sparkles"
                            )
                            .foregroundStyle(.purple)
                        }
                        .font(.caption.monospacedDigit())
                    }
                    .padding(.vertical, 2)
                }
            }
            .navigationTitle("Latency Breakdown")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !timingStore.recent.isEmpty {
                        Button("Clear", role: .destructive) {
                            timingStore.clearHistory()
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct OrbPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 1.0), value: configuration.isPressed)
    }
}
