#if os(macOS)
    import AppKit
    import AVFoundation
    import Combine
    import SwiftUI
    import UniformTypeIdentifiers

    @available(macOS 15.0, *)
    public struct MacDictationShaderWorkbenchView: View {
        private enum ExportSizeChoice: String, CaseIterable, Identifiable {
            case canvas = "Canvas"
            case window = "Window"
            case screen = "Screen"
            case custom = "Custom"

            var id: Self { self }
        }

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
        @State private var selectedTheme: MacDictationShaderTheme = .defaultTheme
        @State private var bodySignal = 0.62
        @State private var presenceSignal = 0.58
        @State private var pulseSignal = 0.24
        @State private var articulationSignal = 0.36
        @State private var isPaused = false
        @State private var frozenTime = 0.0
        @State private var startDate = Date()
        @State private var surfaceWidth = 960.0
        @State private var surfaceHeight = 660.0
        @State private var exportSizeChoice: ExportSizeChoice = .screen
        @State private var exportWidth = 2560.0
        @State private var exportHeight = 1440.0
        @State private var isExportingPNG = false
        @State private var exportStatusText: String?
        @State private var useLiveMicrophone = false
        @State private var microphoneStatusText: String?
        @State private var topHex = "#F2F4FA"
        @State private var midHex = "#DCE0E8"
        @State private var lowHex = "#B7BCC8"
        @StateObject private var microphoneMonitor = MacDictationShaderWorkbenchMicrophoneMonitor()

        public init() {}

        public var body: some View {
            VStack(spacing: 18) {
                header

                HStack(alignment: .top, spacing: 18) {
                    previewCard
                        .frame(minWidth: 920, maxWidth: .infinity, minHeight: 680, alignment: .center)

                    controlsCard
                        .frame(width: 320, alignment: .topLeading)
                }
            }
            .padding(20)
            .frame(minWidth: 1360, minHeight: 920)
            .background(
                LinearGradient(
                    colors: [
                        Color(nsColor: .windowBackgroundColor),
                        Color(nsColor: .controlBackgroundColor).opacity(0.92),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .onAppear {
                syncThemePreset()
                if useLiveMicrophone {
                    Task { @MainActor in
                        await updateMicrophoneMonitoring(isEnabled: true)
                    }
                }
            }
            .onChange(of: selectedState) { _, _ in
                syncThemePreset()
            }
            .onChange(of: selectedTheme) { _, _ in
                syncThemePreset()
            }
            .onChange(of: useLiveMicrophone) { _, isEnabled in
                Task { @MainActor in
                    await updateMicrophoneMonitoring(isEnabled: isEnabled)
                }
            }
            .onDisappear {
                microphoneMonitor.stop()
            }
        }

        private var header: some View {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Shader Debug Window")
                        .font(.title2.weight(.semibold))

                    Text("Large preview surface with direct hex color input and optional live mic input.")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 10) {
                    Button("Export PNG") {
                        Task { @MainActor in
                            await exportPNG()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isExportingPNG)

                    Button(isPaused ? "Resume" : "Pause") {
                        if isPaused {
                            startDate = Date().addingTimeInterval(-frozenTime)
                        } else {
                            frozenTime = currentElapsed
                        }
                        isPaused.toggle()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }

        private var previewCard: some View {
            VStack(alignment: .leading, spacing: 12) {
                shaderCanvas(size: CGSize(width: surfaceWidth, height: surfaceHeight))
                    .frame(minHeight: 680)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .strokeBorder(.quaternary, lineWidth: 1)
                    )

                HStack {
                    Text(summaryText)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    if let exportStatusText {
                        Text(exportStatusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button("Reset Time") {
                        startDate = Date()
                        frozenTime = 0
                    }
                    .buttonStyle(.bordered)
                }
            }
        }

        private var controlsCard: some View {
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

                GroupBox("Color codes") {
                    VStack(alignment: .leading, spacing: 10) {
                        hexField(title: "Top", text: $topHex)
                        hexField(title: "Mid", text: $midHex)
                        hexField(title: "Low", text: $lowHex)
                    }
                    .padding(.top, 2)
                }

                GroupBox("Signals") {
                    VStack(alignment: .leading, spacing: 10) {
                        labeledSlider(title: "Body", value: $bodySignal)
                        labeledSlider(title: "Presence", value: $presenceSignal)
                        labeledSlider(title: "Pulse", value: $pulseSignal)
                        labeledSlider(title: "Articulation", value: $articulationSignal)
                    }
                    .padding(.top, 2)
                }
                .disabled(useLiveMicrophone)

                Toggle("Use live microphone", isOn: $useLiveMicrophone)

                if useLiveMicrophone {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(microphoneStatusText ?? microphoneMonitor.statusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(signalSourceSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle("Pause timeline", isOn: $isPaused)

                labeledSlider(title: "Width", value: $surfaceWidth, range: 480...1200)
                labeledSlider(title: "Height", value: $surfaceHeight, range: 300...900)

                GroupBox("Export size") {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Export size", selection: $exportSizeChoice) {
                            ForEach(ExportSizeChoice.allCases) { choice in
                                Text(choice.rawValue).tag(choice)
                            }
                        }
                        .pickerStyle(.menu)

                        if exportSizeChoice == .custom {
                            HStack {
                                labeledNumberField(title: "W", value: $exportWidth)
                                labeledNumberField(title: "H", value: $exportHeight)
                            }
                        } else {
                            Text(exportDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 2)
                }

                Spacer(minLength: 0)
            }
        }

        private var summaryText: String {
            "state=\(selectedState.rawValue.lowercased()) theme=\(selectedTheme.rawValue) source=\(useLiveMicrophone ? "mic" : "manual") top=\(topHex) mid=\(midHex) low=\(lowHex)"
        }

        private var resolvedSignals: MacDictationCapsuleVisualSignals {
            if useLiveMicrophone {
                return microphoneMonitor.visualSignals
            }

            return MacDictationCapsuleVisualSignals(
                body: bodySignal,
                presence: presenceSignal,
                pulse: pulseSignal,
                articulation: articulationSignal
            )
        }

        private var signalSourceSummary: String {
            if useLiveMicrophone {
                return "Signals are driven from the active microphone input."
            }

            return "Signals are driven from manual slider input."
        }

        private var currentElapsed: Double {
            if isPaused {
                return frozenTime
            }

            return Date().timeIntervalSince(startDate)
        }

        private var exportDescription: String {
            switch exportSizeChoice {
            case .canvas:
                return "Uses the current shader canvas size."
            case .window:
                return "Uses the debug window size."
            case .screen:
                return "Uses the main screen size."
            case .custom:
                return "Uses the custom export size."
            }
        }

        @MainActor
        private func updateMicrophoneMonitoring(isEnabled: Bool) async {
            if isEnabled {
                microphoneStatusText = nil
                do {
                    try await microphoneMonitor.start()
                } catch {
                    microphoneStatusText = "Microphone unavailable: \(error.localizedDescription)"
                    useLiveMicrophone = false
                    microphoneMonitor.stop()
                }
            } else {
                microphoneStatusText = nil
                microphoneMonitor.stop()
            }
        }

        private func syncThemePreset() {
            let palette = selectedTheme.palette
            let target: MacDictationShaderThemeColorSet
            switch selectedState {
            case .hidden:
                target = palette.idle
            case .starting:
                target = palette.starting
            case .listening:
                target = palette.speaking
            case .processing:
                target = palette.processing
            case .result:
                target = palette.speaking
            }

            topHex = Self.hexString(from: target.top)
            midHex = Self.hexString(from: target.mid)
            lowHex = Self.hexString(from: target.low)
        }

        private func manualColors(elapsed _: Double, detail _: Double, signals _: MacDictationCapsuleVisualSignals) -> (
            top: Color, mid: Color, low: Color
        ) {
            (
                top: Self.color(fromHex: topHex) ?? .white,
                mid: Self.color(fromHex: midHex) ?? .white,
                low: Self.color(fromHex: lowHex) ?? .white
            )
        }

        @ViewBuilder
        private func shaderCanvas(size: CGSize) -> some View {
            TimelineView(.animation(minimumInterval: 1.0 / 40.0, paused: isPaused)) { timeline in
                let elapsed = isPaused ? frozenTime : timeline.date.timeIntervalSince(startDate)
                let signals = resolvedSignals
                let detail = MacDictationShaderStyling.detail(
                    for: selectedState.visualState,
                    signals: signals
                )
                let colors = manualColors(
                    elapsed: elapsed,
                    detail: detail,
                    signals: signals
                )

                shaderCanvasContents(
                    size: size,
                    elapsed: elapsed,
                    signals: signals,
                    detail: detail,
                    colors: colors
                )
            }
        }

        @ViewBuilder
        private func shaderCanvasContents(
            size: CGSize,
            elapsed: Double,
            signals: MacDictationCapsuleVisualSignals,
            detail: Double,
            colors: (top: Color, mid: Color, low: Color)
        ) -> some View {
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
                            size: size,
                            time: elapsed,
                            body: signals.body,
                            presence: signals.presence,
                            pulse: signals.pulse,
                            articulation: signals.articulation,
                            detail: detail,
                            top: colors.top,
                            mid: colors.mid,
                            low: colors.low
                        )
                    )
                    .frame(width: size.width, height: size.height)
                    .shadow(color: .black.opacity(0.12), radius: 16, y: 10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(20)
        }

        @ViewBuilder
        private func labeledNumberField(title: String, value: Binding<Double>) -> some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)

                TextField("", value: value, format: .number.precision(.fractionLength(0)))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 76)
            }
        }

        @ViewBuilder
        private func hexField(title: String, text: Binding<String>) -> some View {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(title)
                    Spacer()
                    Text("#RRGGBB")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)

                TextField("#RRGGBB", text: text)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .autocorrectionDisabled()
                    .onChange(of: text.wrappedValue) { _, newValue in
                        text.wrappedValue = normalizedHexInput(newValue)
                    }
            }
        }

        @ViewBuilder
        private func labeledSlider(title: String, value: Binding<Double>, range: ClosedRange<Double> = 0...1)
            -> some View
        {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(title)
                    Spacer()
                    Text(value.wrappedValue.formatted(.number.precision(.fractionLength(2))))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .font(.caption)

                Slider(value: value, in: range)
            }
        }

        private func normalizedHexInput(_ input: String) -> String {
            var value = input.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if !value.hasPrefix("#") {
                value = "#" + value
            }

            let hexDigits = value.dropFirst().filter { $0.isHexDigit }
            let limited = String(hexDigits.prefix(6))
            return "#" + limited
        }

        private static func color(fromHex hex: String) -> Color? {
            let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count == 7, trimmed.first == "#" else { return nil }

            let hexPart = String(trimmed.dropFirst())
            guard let value = Int(hexPart, radix: 16) else { return nil }

            let red = Double((value >> 16) & 0xFF) / 255.0
            let green = Double((value >> 8) & 0xFF) / 255.0
            let blue = Double(value & 0xFF) / 255.0
            return Color(red: red, green: green, blue: blue)
        }

        @MainActor
        private func exportPNG() async {
            guard !isExportingPNG else { return }
            isExportingPNG = true
            defer { isExportingPNG = false }

            let exportSize = resolvedExportSize()
            let elapsed = currentElapsed
            let signals = resolvedSignals
            let detail = MacDictationShaderStyling.detail(
                for: selectedState.visualState,
                signals: signals
            )
            let colors = manualColors(elapsed: elapsed, detail: detail, signals: signals)

            let exportView = shaderCanvasContents(
                size: exportSize,
                elapsed: elapsed,
                signals: signals,
                detail: detail,
                colors: colors
            )
            .frame(width: exportSize.width, height: exportSize.height)
            .background(Color.clear)

            let renderer = ImageRenderer(content: exportView)
            renderer.scale = 1
            renderer.proposedSize = ProposedViewSize(exportSize)

            guard let image = renderer.nsImage,
                let tiffData = image.tiffRepresentation,
                let bitmap = NSBitmapImageRep(data: tiffData),
                let pngData = bitmap.representation(using: .png, properties: [:])
            else {
                exportStatusText = "Export failed"
                return
            }

            let panel = NSSavePanel()
            panel.allowedContentTypes = [.png]
            panel.canCreateDirectories = true
            panel.nameFieldStringValue = "stet-shader.png"
            panel.title = "Export Shader PNG"
            panel.message = "Choose where to save the shader image."

            let response = panel.runModal()
            guard response == .OK, let url = panel.url else {
                exportStatusText = "Export cancelled"
                return
            }

            do {
                try pngData.write(to: url, options: [.atomic])
                exportStatusText = "Exported PNG"
            } catch {
                exportStatusText = "Export failed"
            }
        }

        private func resolvedExportSize() -> CGSize {
            switch exportSizeChoice {
            case .canvas:
                return CGSize(width: surfaceWidth, height: surfaceHeight)
            case .window:
                return CGSize(width: 1160, height: 820)
            case .screen:
                if let screen = NSScreen.main {
                    return screen.frame.size
                }
                return CGSize(width: 1920, height: 1080)
            case .custom:
                return CGSize(width: max(exportWidth, 1), height: max(exportHeight, 1))
            }
        }

        private static func hexString(from components: (Double, Double, Double)) -> String {
            let red = Int((components.0 * 255.0).rounded())
            let green = Int((components.1 * 255.0).rounded())
            let blue = Int((components.2 * 255.0).rounded())
            return String(format: "#%02X%02X%02X", red, green, blue)
        }
    }

    @MainActor
    final class MacDictationShaderWorkbenchMicrophoneMonitor: ObservableObject {
        @Published private(set) var visualSignals = MacDictationCapsuleVisualSignals.zero
        @Published private(set) var statusText = "Microphone is off."

        private enum Timing {
            static let bodyAttack: TimeInterval = 0.12
            static let bodyRelease: TimeInterval = 0.22
            static let fastAttack: TimeInterval = 0.026
            static let fastRelease: TimeInterval = 0.08
            static let presenceAttack: TimeInterval = 0.05
            static let presenceRelease: TimeInterval = 0.14
            static let pulseAttack: TimeInterval = 0.012
            static let pulseRelease: TimeInterval = 0.06
            static let articulationAttack: TimeInterval = 0.02
            static let articulationRelease: TimeInterval = 0.08
            static let minimumTimeConstant: TimeInterval = 0.001
        }

        private struct State {
            var body: Double
            var fast: Double
            var presence: Double
            var pulse: Double
            var articulation: Double
        }

        private let levelBridge = MicrophoneLevelBridge()
        private var audioEngine: AVAudioEngine?
        private var levelTask: Task<Void, Never>?
        private var signalState = State(body: 0, fast: 0, presence: 0, pulse: 0, articulation: 0)
        private var isRunning = false

        func start() async throws {
            guard !isRunning else { return }

            statusText = "Requesting microphone access..."
            let granted = await requestMicrophoneAccess()
            guard granted else {
                statusText = "Microphone access denied."
                throw CocoaError(.fileReadNoPermission)
            }

            let engine = AVAudioEngine()
            let inputNode = engine.inputNode
            let format = inputNode.inputFormat(forBus: 0)
            let levelBridge = self.levelBridge

            signalState = State(body: 0.08, fast: 0.08, presence: 0.08, pulse: 0, articulation: 0.08)
            publishSignals(from: signalState)

            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in
                levelBridge.emit(Self.normalizedLevel(from: buffer))
            }

            do {
                try engine.start()
            } catch {
                inputNode.removeTap(onBus: 0)
                statusText = "Microphone failed to start: \(error.localizedDescription)"
                throw error
            }

            audioEngine = engine
            isRunning = true
            statusText = "Microphone live."

            levelTask?.cancel()
            levelTask = Task { [weak self] in
                let stream = self?.levelBridge.makeStream() ?? AsyncStream<Double> { continuation in
                    continuation.finish()
                }

                for await level in stream {
                    guard !Task.isCancelled else { break }
                    await MainActor.run {
                        self?.advance(level: level)
                    }
                }
            }
        }

        func stop() {
            levelTask?.cancel()
            levelTask = nil

            audioEngine?.inputNode.removeTap(onBus: 0)
            audioEngine?.stop()
            audioEngine = nil

            isRunning = false
            signalState = State(body: 0, fast: 0, presence: 0, pulse: 0, articulation: 0)
            visualSignals = .zero
            statusText = "Microphone is off."
        }

        private func advance(level: Double) {
            let deltaTime = 1.0 / 40.0
            let target = Self.amplifiedLevel(level)

            let nextFast = smooth(
                current: signalState.fast,
                target: target,
                deltaTime: deltaTime,
                attack: Timing.fastAttack,
                release: Timing.fastRelease
            )

            let nextBody = smooth(
                current: signalState.body,
                target: target,
                deltaTime: deltaTime,
                attack: Timing.bodyAttack,
                release: Timing.bodyRelease
            )

            let transient = max(0, nextFast - nextBody)
            let pulseTarget = min(1, transient * 4.2 + target * 0.10)
            let nextPulse = smooth(
                current: signalState.pulse,
                target: pulseTarget,
                deltaTime: deltaTime,
                attack: Timing.pulseAttack,
                release: Timing.pulseRelease
            )

            let nextPresence = smooth(
                current: signalState.presence,
                target: Self.presenceTarget(body: nextBody, fast: nextFast),
                deltaTime: deltaTime,
                attack: Timing.presenceAttack,
                release: Timing.presenceRelease
            )

            let articulationTarget = min(
                1,
                transient * 2.0
                    + max(0, nextFast - nextPresence * 0.66) * 1.02
                    + target * 0.22
            )
            let nextArticulation = smooth(
                current: signalState.articulation,
                target: articulationTarget,
                deltaTime: deltaTime,
                attack: Timing.articulationAttack,
                release: Timing.articulationRelease
            )

            signalState = State(
                body: nextBody,
                fast: nextFast,
                presence: nextPresence,
                pulse: nextPulse,
                articulation: nextArticulation
            )
            publishSignals(from: signalState)
        }

        private func publishSignals(from state: State) {
            visualSignals = MacDictationCapsuleVisualSignals(
                body: state.body,
                presence: state.presence,
                pulse: state.pulse,
                articulation: state.articulation
            )
        }

        private func requestMicrophoneAccess() async -> Bool {
            switch AVAudioApplication.shared.recordPermission {
            case .granted:
                return true
            case .denied:
                return false
            case .undetermined:
                return await withCheckedContinuation { continuation in
                    AVAudioApplication.requestRecordPermission { granted in
                        continuation.resume(returning: granted)
                    }
                }
            @unknown default:
                return false
            }
        }

        private func smooth(
            current: Double,
            target: Double,
            deltaTime: TimeInterval,
            attack: TimeInterval,
            release: TimeInterval
        ) -> Double {
            let timeConstant = target > current ? attack : release
            let alpha = 1.0 - exp(-deltaTime / max(timeConstant, Timing.minimumTimeConstant))
            return current + (target - current) * alpha
        }

        private static func presenceTarget(body: Double, fast: Double) -> Double {
            min(1, max(body * 1.16 + fast * 0.58, fast * 1.02))
        }

        private static func amplifiedLevel(_ value: Double) -> Double {
            min(max(value * 1.68, 0), 1)
        }

        private static func normalizedLevel(from buffer: AVAudioPCMBuffer) -> Double {
            guard let channelData = buffer.floatChannelData else {
                return 0.08
            }

            let frameLength = Int(buffer.frameLength)
            let channelCount = Int(buffer.format.channelCount)
            guard frameLength > 0, channelCount > 0 else {
                return 0.08
            }

            var sum: Float = 0

            for channel in 0..<channelCount {
                let samples = channelData[channel]

                for index in 0..<frameLength {
                    let sample = samples[index]
                    sum += sample * sample
                }
            }

            let meanSquare = sum / Float(frameLength * channelCount)
            let rms = sqrt(meanSquare)
            return min(max(Double(rms) * 3.2, 0.08), 1)
        }
    }

    private final class MicrophoneLevelBridge: @unchecked Sendable {
        private let lock = NSLock()
        private var continuations: [UUID: AsyncStream<Double>.Continuation] = [:]

        func makeStream() -> AsyncStream<Double> {
            let identifier = UUID()

            return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
                lock.lock()
                continuations[identifier] = continuation
                lock.unlock()

                continuation.onTermination = { [weak self] _ in
                    self?.removeContinuation(for: identifier)
                }
            }
        }

        func emit(_ level: Double) {
            let currentContinuations = withContinuations { Array($0.values) }
            for continuation in currentContinuations {
                continuation.yield(level)
            }
        }

        private func removeContinuation(for identifier: UUID) {
            lock.lock()
            continuations.removeValue(forKey: identifier)
            lock.unlock()
        }

        private func withContinuations<T>(_ operation: (inout [UUID: AsyncStream<Double>.Continuation]) -> T) -> T {
            lock.lock()
            defer { lock.unlock() }
            return operation(&continuations)
        }
    }

    #if DEBUG
        #Preview("Shader Debug Window") {
            if #available(macOS 15.0, *) {
                MacDictationShaderWorkbenchView()
            } else {
                Text("Requires macOS 15 or newer")
                    .padding()
            }
        }
    #endif
#endif
