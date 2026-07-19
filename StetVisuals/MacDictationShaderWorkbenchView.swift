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

        @State private var selectedTheme: MacDictationShaderTheme = .egg
        @State private var isPaused = false
        @State private var startDate = Date()
        @State private var surfaceWidth = 960.0
        @State private var surfaceHeight = 660.0
        @State private var exportSizeChoice: ExportSizeChoice = .screen
        @State private var exportWidth = 2560.0
        @State private var exportHeight = 1440.0
        @State private var isExportingPNG = false
        @State private var exportStatusText: String?
        @State private var useLiveMicrophone = true
        @State private var microphoneStatusText: String?
        @State private var hexA = "#F2F4FA"
        @State private var hexB = "#7AAEFF"
        @State private var hexC = "#0A3CA9"
        @State private var motionGain = 1.0
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
                Task { @MainActor in
                    await updateMicrophoneMonitoring(isEnabled: useLiveMicrophone)
                }
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

                    Text("Native Metal translation of the audio field pipeline with live microphone input.")
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
                            startDate = Date()
                        }
                        isPaused.toggle()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }

        private var previewCard: some View {
            VStack(alignment: .leading, spacing: 12) {
                previewSurface(size: CGSize(width: surfaceWidth, height: surfaceHeight))
                    .frame(minHeight: 680)
                    .overlay(
                        Rectangle()
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
                    }
                    .buttonStyle(.bordered)
                }
            }
        }

        private var controlsCard: some View {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Theme", selection: $selectedTheme) {
                    ForEach(MacDictationShaderTheme.allCases) { theme in
                        Text(theme.title).tag(theme)
                    }
                }

                GroupBox("Color codes") {
                    VStack(alignment: .leading, spacing: 10) {
                        hexField(title: "Foam", text: $hexA)
                        hexField(title: "Wave", text: $hexB)
                        hexField(title: "Deep", text: $hexC)
                    }
                    .padding(.top, 2)
                }

                Toggle("Use live microphone", isOn: $useLiveMicrophone)

                VStack(alignment: .leading, spacing: 6) {
                    Text(microphoneStatusText ?? microphoneMonitor.statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(liveSignalSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Toggle("Pause timeline", isOn: $isPaused)

                labeledSlider(title: "Motion gain", value: $motionGain, range: 0.2...2.0)
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
            "theme=\(selectedTheme.rawValue) source=\(useLiveMicrophone ? "mic" : "idle") foam=\(hexA) wave=\(hexB) deep=\(hexC)"
        }

        private var resolvedSignals: MacDictationCapsuleVisualSignals {
            useLiveMicrophone ? microphoneMonitor.visualSignals : .zero
        }

        private var liveSignalSummary: String {
            let summary = resolvedSignals.estimatedSummary
            return
                "level=\(summary.level.formatted(.number.precision(.fractionLength(2)))) flow=(\(summary.flowX.formatted(.number.precision(.fractionLength(2)))), \(summary.flowY.formatted(.number.precision(.fractionLength(2)))))"
        }

        private var exportDescription: String {
            switch exportSizeChoice {
            case .canvas:
                return "Uses the current preview size."
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
            let palette = selectedTheme.palette.speaking
            hexA = Self.hexString(from: palette.a)
            hexB = Self.hexString(from: palette.b)
            hexC = Self.hexString(from: palette.c)
        }

        @ViewBuilder
        private func previewSurface(size: CGSize) -> some View {
            let colors = resolvedColors
            ZStack {
                Rectangle()
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

                MacDictationMetalEffectView(
                    size: size,
                    startDate: startDate,
                    frameInterval: 1.0 / 40.0,
                    signals: resolvedSignals,
                    colors: colors,
                    isPaused: isPaused,
                    motionGain: Float(motionGain)
                )
                .frame(width: size.width, height: size.height)
            }
            .padding(20)
        }

        private var resolvedColors: (cottonFoam: Color, waveTop: Color, deepSea: Color) {
            (
                cottonFoam: Self.color(fromHex: hexA) ?? .white,
                waveTop: Self.color(fromHex: hexB) ?? .white,
                deepSea: Self.color(fromHex: hexC) ?? .blue
            )
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
        private func labeledSlider(title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
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
            let exportView = previewSurface(size: exportSize)
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

        private let analyzer = MacDictationAudioFeatureAnalyzer()
        private var audioEngine: AVAudioEngine?
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

            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
                guard let self, let analyzer = self.analyzer else { return }
                let signals = analyzer.analyze(buffer: buffer)
                Task { @MainActor in
                    self.visualSignals = signals
                }
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
        }

        func stop() {
            audioEngine?.inputNode.removeTap(onBus: 0)
            audioEngine?.stop()
            audioEngine = nil
            isRunning = false
            visualSignals = .zero
            statusText = "Microphone is off."
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
