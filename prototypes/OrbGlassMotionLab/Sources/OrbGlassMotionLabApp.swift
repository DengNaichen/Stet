import SwiftUI

@main
struct OrbGlassMotionLabApp: App {
    var body: some Scene {
        WindowGroup("Orb Glass Motion Lab") {
            MotionLabView()
        }
        .defaultSize(width: 980, height: 710)
        .windowResizability(.contentMinSize)
    }
}

private enum Trajectory: String, CaseIterable, Identifiable {
    case line = "直线", arc = "浅弧", swing = "下摆"
    var id: Self { self }

    func point(_ t: Double, side: CGFloat, reach: Double, drop: Double, bend: Double) -> CGPoint {
        if self == .line {
            return CGPoint(x: side * reach * t, y: drop * t)
        }
        let y1 = self == .arc ? -bend : bend + drop
        let y2 = self == .arc ? -bend * 0.7 : bend + drop
        let u = 1 - t
        let x = 3*u*u*t*(reach*0.22) + 3*u*t*t*(reach*0.74) + t*t*t*reach
        let y = 3*u*u*t*y1 + 3*u*t*t*y2 + t*t*t*drop
        return CGPoint(x: side*x, y: y)
    }
}

private struct MotionSettings {
    var trajectory = Trajectory.arc
    var reach = 60.0
    var drop = 12.0
    var bend = 12.0
    var duration = 0.55
    var glassSpacing = 10.0
    var showPath = false
    var showPaint = true
    var animatePaint = false
    var backdrop = 0
}

private struct Playback {
    let from: Double
    let to: Double
    let start: Date
    let duration: Double

    func progress(at date: Date) -> Double {
        let t = min(1, max(0, date.timeIntervalSince(start)/duration))
        let eased = t*t*(3-2*t)
        return from + (to-from)*eased
    }
    func finished(at date: Date) -> Bool { date.timeIntervalSince(start) >= duration }
}

private struct MotionLabView: View {
    @State private var settings = MotionSettings()
    @State private var manualProgress = 1.0
    @State private var playback: Playback?
    @State private var paintStart = Date()
    @State private var feedback = "拖动展开进度，可以检查玻璃分离的中间帧。"

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0/60.0, paused: playback == nil && !settings.animatePaint)) { context in
            let progress = playback?.progress(at: context.date) ?? manualProgress
            let paintTime = settings.animatePaint ? context.date.timeIntervalSince(paintStart)+3 : 3
            VStack(spacing: 20) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Liquid Glass · 展开实验").font(.title2.weight(.semibold))
                        Text("圆球 64 · 按钮 28 · 点击区域 44").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("背景", selection: $settings.backdrop) {
                        Text("浅色").tag(0)
                        Text("深色").tag(1)
                        Text("色块").tag(2)
                    }.pickerStyle(.segmented).frame(width: 210)
                }

                HStack(spacing: 16) {
                    preview(title: "实际大小", scale: 1, progress: progress, paintTime: paintTime)
                    preview(title: "放大观察 · 2×", scale: 2, progress: progress, paintTime: paintTime)
                }

                VStack(spacing: 17) {
                    HStack(spacing: 10) {
                        Button("重播展开", systemImage: "arrow.counterclockwise") { play(to: 1, replay: true) }
                            .buttonStyle(.borderedProminent)
                        Button("收回") { play(to: 0) }
                        Button("展开") { play(to: 1) }
                        Spacer()
                        Picker("轨迹", selection: $settings.trajectory) {
                            ForEach(Trajectory.allCases) { item in Text(item.rawValue).tag(item) }
                        }.pickerStyle(.segmented).frame(width: 210)
                    }
                    HStack(spacing: 14) {
                        Text("展开进度").frame(width: 62, alignment: .leading)
                        Slider(value: Binding(get: { progress }, set: { playback = nil; manualProgress = $0 }), in: 0...1)
                            .accessibilityLabel("展开进度")
                        Text("\(Int(progress*100))%").monospacedDigit().frame(width: 42, alignment: .trailing)
                    }
                    HStack(spacing: 28) {
                        parameter("水平展开", value: $settings.reach, range: 48...84, suffix: "pt")
                        parameter("最终下移", value: $settings.drop, range: 0...28, suffix: "pt")
                        parameter("弧线幅度", value: $settings.bend, range: 0...30, suffix: "pt")
                    }
                    HStack(spacing: 28) {
                        parameter("玻璃融合距离", value: $settings.glassSpacing, range: 0...28, suffix: "pt")
                        parameter("动画时长", value: $settings.duration, range: 0.25...1.6, suffix: "s")
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("显示轨迹", isOn: $settings.showPath)
                            HStack {
                                Toggle("显示水彩", isOn: $settings.showPaint)
                                Toggle("水彩流动", isOn: $settings.animatePaint).disabled(!settings.showPaint)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).toggleStyle(.checkbox)
                    }
                }
                .font(.subheadline)

                HStack {
                    Text(feedback).foregroundStyle(.secondary)
                    Spacer()
                    Text("水平边缘间距 \(Int(settings.reach-46)) pt · \(settings.trajectory.rawValue)")
                        .monospacedDigit().foregroundStyle(.secondary)
                }.font(.caption)
            }
            .padding(28)
            .frame(minWidth: 900, minHeight: 640)
            .background(Color(nsColor: .windowBackgroundColor))
            .preferredColorScheme(settings.backdrop == 1 ? .dark : .light)
            .onChange(of: context.date) { _, date in
                if let playback, playback.finished(at: date) {
                    manualProgress = playback.to
                    self.playback = nil
                }
            }
        }
    }

    private func parameter(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, suffix: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title).foregroundStyle(.secondary)
                Spacer()
                Text(suffix == "s" ? String(format: "%.2f s", value.wrappedValue) : "\(Int(value.wrappedValue)) pt")
                    .monospacedDigit()
            }
            Slider(value: value, in: range).accessibilityLabel(title)
        }.frame(maxWidth: .infinity)
    }

    private func preview(title: String, scale: CGFloat, progress: Double, paintTime: Double) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.caption).foregroundStyle(.secondary).padding(16)
            GlassAssembly(progress: progress, settings: settings, paintTime: paintTime) { label in
                feedback = "\(label) · 仅演示按钮交互"
            }
            .frame(width: 210, height: 100)
            .scaleEffect(scale)
            .frame(maxWidth: .infinity, minHeight: 210, maxHeight: 210)
            Spacer(minLength: 12)
        }
        .background {
            ZStack {
                if settings.backdrop == 2 {
                    LinearGradient(colors: [Color(red: 0.85, green: 0.90, blue: 0.98), Color(red: 0.96, green: 0.86, blue: 0.80), Color(red: 0.72, green: 0.87, blue: 0.83)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.4))
                        .frame(width: 150, height: 46).rotationEffect(.degrees(-18)).offset(x: 70, y: 13)
                } else {
                    Color.primary.opacity(settings.backdrop == 1 ? 0.04 : 0.025)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.primary.opacity(0.06)))
    }

    private func play(to target: Double, replay: Bool = false) {
        let now = Date()
        let from = replay ? 0 : playback?.progress(at: now) ?? manualProgress
        manualProgress = from
        playback = Playback(from: from, to: target, start: now, duration: settings.duration)
    }
}

private struct GlassAssembly: View {
    let progress: Double
    let settings: MotionSettings
    let paintTime: Double
    let action: (String) -> Void
    @Namespace private var glassNamespace

    var body: some View {
        ZStack {
            if settings.showPath {
                Path { path in
                    for side in [CGFloat(-1),CGFloat(1)] {
                        for step in 0...80 {
                            let p = position(Double(step)/80, side: side)
                            let point = CGPoint(x: 105+p.x, y: 50+p.y)
                            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
                        }
                    }
                }
                .stroke(Color.accentColor.opacity(0.55), style: StrokeStyle(lineWidth: 0.7, dash: [2,3]))
                .allowsHitTesting(false)
            }
            // Match Stet's composition: one shared glass container, paint above it.
            // Timeline sampling positions every frame follows the complete curve,
            // rather than asking SwiftUI to interpolate only its two endpoints.
            GlassEffectContainer(spacing: settings.glassSpacing) {
                ZStack {
                    glassButton("xmark", label: "取消", id: "cancel", side: -1)
                    glassButton("checkmark", label: "确认", id: "confirm", side: 1)
                    Color.clear.frame(width: 64, height: 64)
                        .glassEffect(.regular.tint(nil), in: Circle())
                        .glassEffectID("main", in: glassNamespace)
                        .allowsHitTesting(false)
                }
            }
            if settings.showPaint {
                Circle().fill(.white)
                    .frame(width: 64, height: 64)
                    .colorEffect(ShaderLibrary.labWatercolor(.float2(64,64), .float(Float(paintTime))))
                    .allowsHitTesting(false)
                    .accessibilityLabel("水彩圆球")
            }
        }
        .frame(width: 210, height: 100)
    }

    private func position(_ t: Double, side: CGFloat) -> CGPoint {
        settings.trajectory.point(t, side: side, reach: settings.reach, drop: settings.drop, bend: settings.bend)
    }

    private func glassButton(_ symbol: String, label: String, id: String, side: CGFloat) -> some View {
        let point = position(progress, side: side)
        return Button { action(label) } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
                .opacity(min(1,max(0,(progress-0.18)/0.35)))
                .frame(width: 28, height: 28)
                .glassEffect(.regular.tint(nil).interactive(), in: Circle())
                .glassEffectID(id, in: glassNamespace)
                .padding(8)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .offset(x: point.x, y: point.y)
        .allowsHitTesting(progress > 0.98)
        .accessibilityHidden(progress <= 0.98)
        .accessibilityLabel(label)
    }
}
