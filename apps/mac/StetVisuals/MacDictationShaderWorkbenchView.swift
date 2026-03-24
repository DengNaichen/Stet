#if os(macOS)
    import AppKit
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
        @State private var topHex = "#F2F4FA"
        @State private var midHex = "#DCE0E8"
        @State private var lowHex = "#B7BCC8"

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
            }
            .onChange(of: selectedState) { _, _ in
                syncThemePreset()
            }
            .onChange(of: selectedTheme) { _, _ in
                syncThemePreset()
            }
        }

        private var header: some View {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Shader Debug Window")
                        .font(.title2.weight(.semibold))

                    Text("Large preview surface with direct hex color input.")
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
            "state=\(selectedState.rawValue.lowercased()) theme=\(selectedTheme.rawValue) top=\(topHex) mid=\(midHex) low=\(lowHex)"
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
                let signals = MacDictationCapsuleVisualSignals(
                    body: bodySignal,
                    presence: presenceSignal,
                    pulse: pulseSignal,
                    articulation: articulationSignal
                )
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
            let signals = MacDictationCapsuleVisualSignals(
                body: bodySignal,
                presence: presenceSignal,
                pulse: pulseSignal,
                articulation: articulationSignal
            )
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
