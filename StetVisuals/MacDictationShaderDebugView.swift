#if os(macOS)
    import SwiftUI

    @available(macOS 15.0, *)
    public struct MacDictationShaderDebugView: View {
        private enum DebugState: String, CaseIterable, Identifiable {
            case hidden = "Hidden"
            case starting = "Starting"
            case listening = "Listening"
            case processing = "Processing"
            case result = "Result"

            var id: Self { self }

            var visualState: MacDictationCapsuleVisualState {
                switch self {
                case .hidden:
                    return .hidden
                case .starting:
                    return .starting
                case .listening:
                    return .listening
                case .processing:
                    return .processing
                case .result:
                    return .result
                }
            }
        }

        @State private var selectedState: DebugState = .listening
        @State private var bodySignal = 0.62
        @State private var presenceSignal = 0.58
        @State private var pulseSignal = 0.24
        @State private var articulationSignal = 0.36
        @State private var useStateDetail = true
        @State private var manualDetail = 1.0
        @State private var selectedTheme: MacDictationShaderTheme = .egg
        @State private var isPaused = false
        @State private var frozenTime = 0.0
        @State private var surfaceWidth = Double(MacDictationPanelConstants.Layout.mainWidthListening)
        @State private var surfaceHeight = Double(MacDictationPanelConstants.Layout.controlHeight)
        @State private var frameInterval = MacDictationPanelConstants.VoiceReactivity.shaderFrameIntervalActive
        @State private var startDate = Date()

        public init() {}

        public var body: some View {
            VStack(alignment: .leading, spacing: 18) {
                previewSection
                controlsSection
            }
            .padding(20)
            .frame(width: 620)
            .background(Color(nsColor: .windowBackgroundColor))
        }

        private var previewSection: some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Capsule Orb Shader")
                            .font(.headline)

                        Text(debugSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Reset Clock") {
                        startDate = Date()
                        frozenTime = 0
                    }
                    .buttonStyle(.bordered)
                }

                TimelineView(.animation(minimumInterval: frameInterval, paused: isPaused)) { timeline in
                    let elapsed = isPaused ? frozenTime : timeline.date.timeIntervalSince(startDate)
                    let signals = MacDictationCapsuleVisualSignals(
                        body: bodySignal,
                        presence: presenceSignal,
                        pulse: pulseSignal,
                        articulation: articulationSignal
                    )
                    let detail =
                        useStateDetail
                        ? MacDictationShaderStyling.detail(
                            for: selectedState.visualState,
                            signals: signals
                        )
                        : manualDetail
                    let colors = MacDictationShaderStyling.colors(
                        for: selectedState.visualState,
                        theme: selectedTheme,
                        elapsed: elapsed,
                        signals: signals
                    )

                    ZStack {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.black.opacity(0.08),
                                        Color.black.opacity(0.02),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )

                        Capsule()
                            .fill(.white)
                            .colorEffect(
                                StetVisualsShaderLibrary.cloudOrbGlassWide(
                                    size: CGSize(width: surfaceWidth, height: surfaceHeight),
                                    time: elapsed,
                                    body: signals.body,
                                    presence: signals.presence,
                                    pulse: signals.pulse,
                                    articulation: signals.articulation,
                                    detail: detail,
                                    a: colors.a,
                                    b: colors.b,
                                    c: colors.c
                                )
                            )
                            .frame(width: surfaceWidth, height: surfaceHeight)
                            .shadow(color: .black.opacity(0.08), radius: 12, y: 8)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: max(CGFloat(surfaceHeight) + 64, 128))
                }
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(.quaternary, lineWidth: 1)
                )
            }
        }

        private var controlsSection: some View {
            VStack(alignment: .leading, spacing: 14) {
                Picker("State", selection: $selectedState) {
                    ForEach(DebugState.allCases) { state in
                        Text(state.rawValue).tag(state)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Theme", selection: $selectedTheme) {
                    ForEach(MacDictationShaderTheme.allCases) { theme in
                        Text(theme.title).tag(theme)
                    }
                }
                .pickerStyle(.menu)

                VStack(alignment: .leading, spacing: 10) {
                    labeledSlider(
                        title: "Body",
                        valueText: bodySignal.formatted(.number.precision(.fractionLength(2))),
                        value: $bodySignal,
                        range: 0...1
                    )

                    labeledSlider(
                        title: "Presence",
                        valueText: presenceSignal.formatted(.number.precision(.fractionLength(2))),
                        value: $presenceSignal,
                        range: 0...1
                    )

                    labeledSlider(
                        title: "Pulse",
                        valueText: pulseSignal.formatted(.number.precision(.fractionLength(2))),
                        value: $pulseSignal,
                        range: 0...1
                    )

                    labeledSlider(
                        title: "Articulation",
                        valueText: articulationSignal.formatted(.number.precision(.fractionLength(2))),
                        value: $articulationSignal,
                        range: 0...1
                    )

                    Toggle("Use Production Detail Curve", isOn: $useStateDetail)

                    labeledSlider(
                        title: "Manual Detail",
                        valueText: manualDetail.formatted(.number.precision(.fractionLength(2))),
                        value: $manualDetail,
                        range: 0...1,
                        disabled: useStateDetail
                    )

                    Toggle("Pause Timeline", isOn: $isPaused)

                    labeledSlider(
                        title: "Time",
                        valueText: frozenTime.formatted(.number.precision(.fractionLength(2))),
                        value: $frozenTime,
                        range: 0...20,
                        disabled: !isPaused
                    )

                    labeledSlider(
                        title: "Width",
                        valueText: Int(surfaceWidth).formatted(),
                        value: $surfaceWidth,
                        range: 160...420
                    )

                    labeledSlider(
                        title: "Height",
                        valueText: Int(surfaceHeight).formatted(),
                        value: $surfaceHeight,
                        range: 28...120
                    )

                    labeledSlider(
                        title: "Frame Interval",
                        valueText: frameInterval.formatted(.number.precision(.fractionLength(3))),
                        value: $frameInterval,
                        range: (1.0 / 120.0)...(1.0 / 10.0)
                    )
                }
            }
        }

        private var debugSummary: String {
            let signals = MacDictationCapsuleVisualSignals(
                body: bodySignal,
                presence: presenceSignal,
                pulse: pulseSignal,
                articulation: articulationSignal
            )
            let detail =
                useStateDetail
                ? MacDictationShaderStyling.detail(
                    for: selectedState.visualState,
                    signals: signals
                )
                : manualDetail

            return
                "state=\(selectedState.rawValue.lowercased()) theme=\(selectedTheme.rawValue) body=\(signals.body.formatted(.number.precision(.fractionLength(2)))) pulse=\(signals.pulse.formatted(.number.precision(.fractionLength(2)))) articulation=\(signals.articulation.formatted(.number.precision(.fractionLength(2)))) detail=\(detail.formatted(.number.precision(.fractionLength(2))))"
        }

        @ViewBuilder
        private func labeledSlider(
            title: String,
            valueText: String,
            value: Binding<Double>,
            range: ClosedRange<Double>,
            disabled: Bool = false
        ) -> some View {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(title)
                    Spacer()
                    Text(valueText)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .font(.caption)

                Slider(value: value, in: range)
                    .disabled(disabled)
            }
        }
    }

    #if DEBUG
        #Preview("Shader Debug") {
            if #available(macOS 15.0, *) {
                MacDictationShaderDebugView()
            } else {
                Text("Requires macOS 15 or newer")
                    .padding()
            }
        }
    #endif

#endif
