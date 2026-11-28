// Adapted from dissolve (https://dissolve.rselmi.com/#/thinking-orb) by Rayan Selmi (MIT)
// and Libraries.dev Thinking Orbs (https://libraries.dev/orbs) by Jakub Antalik (MIT).
import CoreGraphics
import Foundation
import SwiftUI
import simd

enum KeyboardThinkingOrbMode: Int, Equatable, CaseIterable {
    case idle = 0
    case thinking = 1
    case searching = 2
    case listening = 3
    case done = 4
    case error = 5
}

private struct KeyboardThinkingOrbDotSeed {
    let sphere: SIMD3<Double>
    let disc: SIMD2<Double>
    let discAngle: Double
    let check: SIMD3<Double>
    let random: Double
}

private struct KeyboardThinkingOrbDotPose {
    var x: Double = 0
    var y: Double = 0
    var z: Double = 0
    var alpha: Double = 1
    var scale: Double = 1
}

private struct KeyboardThinkingOrbRenderDot {
    let center: CGPoint
    let diameter: CGFloat
    let alpha: Double
}

private struct KeyboardThinkingOrbRenderFrame {
    let dots: [KeyboardThinkingOrbRenderDot]
    let color: SIMD3<Double>
}

private enum KeyboardThinkingOrbPreset {
    static let dotCount = 180
    static let referenceDiameter = 64.0
    static let radiusFactor = 0.41
    static let baseDotDiameter = 2.35
    static let morphDuration = 0.600
    static let reducedMorphDuration = 0.150
    static let staggerSeconds = 0.0015
    static let activeFrameInterval = 1.0 / 60.0
    static let idleFrameInterval = 1.0 / 30.0
}

/// Evaluates the dissolve calm iOS cubic-bezier curve (0.32, 0.72, 0.0, 1.0).
private enum KeyboardThinkingOrbEasing {
    private static let x1 = 0.32
    private static let y1 = 0.72
    private static let x2 = 0.0
    private static let y2 = 1.0

    static func calm(_ t: Double) -> Double {
        if t <= 0 { return 0 }
        if t >= 1 { return 1 }

        var u = t
        for _ in 0..<6 {
            let x = sampleX(u) - t
            if abs(x) < 1e-6 { break }
            let dx = sampleDX(u)
            if abs(dx) < 1e-6 { break }
            u = min(1, max(0, u - x / dx))
        }

        if abs(sampleX(u) - t) > 1e-4 {
            var lo = 0.0
            var hi = 1.0
            for _ in 0..<12 {
                let mid = 0.5 * (lo + hi)
                if sampleX(mid) < t {
                    lo = mid
                } else {
                    hi = mid
                }
            }
            u = 0.5 * (lo + hi)
        }

        return sampleY(u)
    }

    private static func sampleX(_ u: Double) -> Double {
        let inv = 1 - u
        return 3 * inv * inv * u * x1 + 3 * inv * u * u * x2 + u * u * u
    }

    private static func sampleDX(_ u: Double) -> Double {
        let inv = 1 - u
        return 3 * inv * inv * x1 + 6 * inv * u * (x2 - x1) + 3 * u * u * (1 - x2)
    }

    private static func sampleY(_ u: Double) -> Double {
        let inv = 1 - u
        return 3 * inv * inv * u * y1 + 3 * inv * u * u * y2 + u * u * u
    }
}

/// Stateful 180-dot particle simulation for the StetKeyboard ThinkingOrb.
private struct KeyboardThinkingOrbEngine {
    private static let tau = Double.pi * 2
    private static let checkPoints: [SIMD2<Double>] = [
        SIMD2(-0.52, 0.02),
        SIMD2(-0.16, 0.38),
        SIMD2(0.56, -0.36),
    ]

    let dotCount: Int
    private let seeds: [KeyboardThinkingOrbDotSeed]

    private var poses: [KeyboardThinkingOrbDotPose]
    private var fromPoses: [KeyboardThinkingOrbDotPose]

    private(set) var mode: KeyboardThinkingOrbMode = .idle
    private var hasAppliedInitialMode = false
    private var elapsedTime = 0.0
    private var modeChangedAt = -100.0
    private var smoothedLevel = 0.0

    private var currentColor = SIMD3<Double>(0.12, 0.12, 0.14)
    private var fromColor = SIMD3<Double>(0.12, 0.12, 0.14)
    private var hasInitializedColor = false

    init(dotCount: Int = KeyboardThinkingOrbPreset.dotCount) {
        let count = max(1, dotCount)
        self.dotCount = count
        self.seeds = Self.makeSeeds(count: count)
        self.poses = Array(repeating: KeyboardThinkingOrbDotPose(), count: count)
        self.fromPoses = Array(repeating: KeyboardThinkingOrbDotPose(), count: count)
    }

    mutating func setMode(_ newMode: KeyboardThinkingOrbMode) {
        guard !hasAppliedInitialMode || newMode != mode else { return }
        if !hasAppliedInitialMode {
            modeChangedAt = -100.0
            hasAppliedInitialMode = true
        } else {
            fromPoses = poses
            fromColor = currentColor
            modeChangedAt = elapsedTime
        }
        mode = newMode
    }

    mutating func step(
        dt rawDT: Double,
        canvasSize: CGSize,
        level: Double?,
        inkColor: SIMD3<Double>,
        successColor: SIMD3<Double>,
        errorColor: SIMD3<Double>,
        reduceMotion: Bool
    ) -> KeyboardThinkingOrbRenderFrame {
        let dt = rawDT.isFinite && rawDT > 0 ? min(rawDT, 0.05) : (1.0 / 60.0)
        elapsedTime += dt
        let t = reduceMotion ? 0.0 : elapsedTime

        let targetColor: SIMD3<Double>
        switch mode {
        case .done:
            targetColor = successColor
        case .error:
            targetColor = errorColor
        default:
            targetColor = inkColor
        }

        if !hasInitializedColor {
            currentColor = targetColor
            fromColor = targetColor
            hasInitializedColor = true
        }

        let since = elapsedTime - modeChangedAt
        let isDone = mode == .done
        let dur =
            reduceMotion
            ? KeyboardThinkingOrbPreset.reducedMorphDuration
            : (isDone ? 0.450 : KeyboardThinkingOrbPreset.morphDuration)
        let stag = reduceMotion ? 0.0 : (isDone ? 0.0010 : KeyboardThinkingOrbPreset.staggerSeconds)

        let tc = min(1.0, max(0.0, since / dur))
        let ec = KeyboardThinkingOrbEasing.calm(tc)
        currentColor = fromColor + (targetColor - fromColor) * ec

        let targetLevel: Double
        if let level, level.isFinite {
            targetLevel = min(1.0, max(0.0, level))
        } else {
            targetLevel = 0.35 + 0.25 * sin(t * 2.3) + 0.10 * sin(t * 5.1)
        }
        let levelTau = targetLevel > smoothedLevel ? 0.05 : 0.22
        smoothedLevel += (targetLevel - smoothedLevel) * (1.0 - exp(-dt / levelTau))

        let spin = t * 0.45
        let cs = cos(spin)
        let sn = sin(spin)
        let tilt = 0.38
        let ct = cos(tilt)
        let stl = sin(tilt)
        let breathe = 0.98 + 0.02 * sin((t * Self.tau) / 2.4)
        let sweep = (t * Self.tau).truncatingRemainder(dividingBy: Self.tau)
        let errT = max(0.0, since)

        // Precessing ribbon plane for the Thinking state.
        let ribbonYaw = t * 0.42
        let ribbonTilt = 0.55 + 0.30 * sin(t * 0.32)
        let rux = cos(ribbonYaw)
        let ruy = 0.0
        let ruz = sin(ribbonYaw)
        let rvx = -ruz * sin(ribbonTilt)
        let rvy = cos(ribbonTilt)
        let rvz = rux * sin(ribbonTilt)
        let rnx = ruy * rvz - ruz * rvy
        let rny = ruz * rvx - rux * rvz
        let rnz = rux * rvy - ruy * rvx
        let ribbonLanes = 5
        let ribbonSegs = max(1, dotCount / ribbonLanes)

        let side = Double(min(canvasSize.width, canvasSize.height))
        let radius = side * KeyboardThinkingOrbPreset.radiusFactor
        let dotBase = max(
            2.2,
            side * (KeyboardThinkingOrbPreset.baseDotDiameter / KeyboardThinkingOrbPreset.referenceDiameter)
        )
        let cx = Double(canvasSize.width) * 0.5
        let cy = Double(canvasSize.height) * 0.5

        var renderDots: [KeyboardThinkingOrbRenderDot] = []
        renderDots.reserveCapacity(dotCount)

        for i in 0..<dotCount {
            let s = seeds[i]
            var x = 0.0
            var y = 0.0
            var z = 0.0
            var a = 1.0

            let ox = s.sphere.x
            let oy = s.sphere.y
            let oz = s.sphere.z
            let rx = ox * cs + oz * sn
            let rz = -ox * sn + oz * cs
            let sy = oy * ct - rz * stl
            let sz = oy * stl + rz * ct

            switch mode {
            case .idle:
                x = rx * breathe
                y = sy * breathe
                z = sz * breathe

            case .thinking:
                let lane = min(ribbonLanes - 1, i / ribbonSegs)
                let seg = i % ribbonSegs
                let halfLanes = Double(ribbonLanes - 1) * 0.5
                let laneOff = (Double(lane) - halfLanes) * 0.095
                let edge = halfLanes > 0 ? abs(Double(lane) - halfLanes) / halfLanes : 0.0
                let ang = (Double(seg) / Double(ribbonSegs)) * Self.tau
                let wob =
                    0.22 * sin(ang * 3.0 - t * 2.2 + Double(lane) * 0.24)
                    + 0.09 * sin(ang * 5.0 + t * 1.4)
                let off = laneOff + wob
                let bx = rux * cos(ang) + rvx * sin(ang) + rnx * off
                let by = ruy * cos(ang) + rvy * sin(ang) + rny * off
                let bz = ruz * cos(ang) + rvz * sin(ang) + rnz * off
                let len = max(1e-6, sqrt(bx * bx + by * by + bz * bz))
                let ux = (bx / len) * 0.96
                let uy = (by / len) * 0.96
                let uz = (bz / len) * 0.96
                x = ux
                y = uy * ct - uz * stl
                z = uy * stl + uz * ct
                a = 1.0 - 0.22 * edge

            case .searching:
                x = s.disc.x * 0.95
                y = s.disc.y * 0.95
                var d = sweep - s.discAngle
                d = (d.truncatingRemainder(dividingBy: Self.tau) + Self.tau)
                    .truncatingRemainder(dividingBy: Self.tau)
                a = 0.3 + 0.7 * exp(-d * 1.4)
                z = a * 0.6 - 0.3

            case .listening:
                let wave = 0.5 + 0.5 * sin(t * 9.0 - (oy + 1.0) * 3.2)
                let rr = 1.0 + smoothedLevel * 0.30 * (0.35 + 0.65 * wave)
                x = rx * rr
                y = sy * rr
                z = sz * rr

            case .done:
                x = s.check.x
                y = s.check.y
                z = s.check.z

            case .error:
                let delay = s.random * 0.18
                let tt = max(0.0, errT - delay)
                let fall = min(1.15, sy + 3.2 * tt * tt)
                let gx = rx * (1.0 + min(tt, 0.9) * 0.35)
                let rawBack = (errT - 1.25 - delay) / 0.6
                let back = rawBack <= 0 ? 0 : (rawBack >= 1 ? 1 : KeyboardThinkingOrbEasing.calm(rawBack))
                x = gx + (rx - gx) * back
                y = fall + (sy - fall) * back
                z = sz
            }

            let dz = min(1.0, max(0.0, (z + 1.0) * 0.5))
            var sc = 0.8 + 0.4 * dz
            a = (0.55 + 0.45 * dz) * a

            let tm = min(1.0, max(0.0, (since - Double(i) * stag) / dur))
            let e = tm >= 1.0 ? 1.0 : KeyboardThinkingOrbEasing.calm(tm)
            if e < 1.0 {
                let f = fromPoses[i]
                x = f.x + (x - f.x) * e
                y = f.y + (y - f.y) * e
                z = f.z + (z - f.z) * e
                a = f.alpha + (a - f.alpha) * e
                sc = f.scale + (sc - f.scale) * e
            }

            poses[i] = KeyboardThinkingOrbDotPose(x: x, y: y, z: z, alpha: a, scale: sc)

            let px = cx + x * radius
            let py = cy + y * radius

            renderDots.append(
                KeyboardThinkingOrbRenderDot(
                    center: CGPoint(x: px, y: py),
                    diameter: CGFloat(dotBase * sc),
                    alpha: min(1.0, max(0.0, a))
                )
            )
        }

        return KeyboardThinkingOrbRenderFrame(dots: renderDots, color: currentColor)
    }

    private static func makeSeeds(count n: Int) -> [KeyboardThinkingOrbDotSeed] {
        let golden = Double.pi * (3.0 - sqrt(5.0))
        let l1 = hypot(checkPoints[1].x - checkPoints[0].x, checkPoints[1].y - checkPoints[0].y)
        let l2 = hypot(checkPoints[2].x - checkPoints[1].x, checkPoints[2].y - checkPoints[1].y)
        let totalLength = l1 + l2

        return (0..<n).map { i in
            let idx = Double(i)
            let nf = Double(n)

            let y = 1.0 - (2.0 * (idx + 0.5)) / nf
            let r = sqrt(max(0.0, 1.0 - y * y))
            let a = idx * golden
            let sphere = SIMD3(cos(a) * r, y, sin(a) * r)

            let dr = sqrt((idx + 0.5) / nf)
            let disc = SIMD2(cos(a) * dr, sin(a) * dr)
            let discAngle = (a.truncatingRemainder(dividingBy: tau) + tau).truncatingRemainder(dividingBy: tau)

            var u = ((idx + 0.5) / nf) * totalLength
            let seg = u < l1 ? 0 : 1
            if seg == 1 { u -= l1 }
            let p0 = checkPoints[seg]
            let p1 = checkPoints[seg + 1]
            let len = seg == 0 ? l1 : l2
            let f = u / len
            let nx = -(p1.y - p0.y) / len
            let ny = (p1.x - p0.x) / len
            let w = (deterministicHash(i, 1) - 0.5) * 0.11
            let check = SIMD3(
                p0.x + (p1.x - p0.x) * f + nx * w,
                p0.y + (p1.y - p0.y) * f + ny * w,
                (deterministicHash(i, 2) - 0.5) * 0.5
            )

            return KeyboardThinkingOrbDotSeed(
                sphere: sphere,
                disc: disc,
                discAngle: discAngle,
                check: check,
                random: deterministicHash(i, 3)
            )
        }
    }

    private static func deterministicHash(_ i: Int, _ k: Int) -> Double {
        let x = sin(Double(i) * 12.9898 + Double(k) * 78.233) * 43758.5453
        return x - floor(x)
    }
}

struct KeyboardThinkingOrbView: View {
    let mode: KeyboardThinkingOrbMode
    let level: Double?
    let diameter: CGFloat
    let isActive: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var engine = KeyboardThinkingOrbEngine()
    @State private var frame = KeyboardThinkingOrbRenderFrame(dots: [], color: SIMD3(0.12, 0.12, 0.14))
    @State private var previousDate: Date?

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: mode == .idle
                    ? KeyboardThinkingOrbPreset.idleFrameInterval
                    : KeyboardThinkingOrbPreset.activeFrameInterval,
                paused: !isActive
            )
        ) { context in
            Canvas { graphics, _ in
                let baseColor = Color(
                    red: frame.color.x,
                    green: frame.color.y,
                    blue: frame.color.z
                )
                for dot in frame.dots {
                    let r = dot.diameter * 0.5
                    let rect = CGRect(
                        x: dot.center.x - r,
                        y: dot.center.y - r,
                        width: dot.diameter,
                        height: dot.diameter
                    )
                    graphics.fill(
                        Path(ellipseIn: rect),
                        with: .color(baseColor.opacity(dot.alpha))
                    )
                }
            }
            .frame(width: diameter, height: diameter)
            .onChange(of: context.date) { _, date in
                let dt =
                    previousDate.map { date.timeIntervalSince($0) } ?? KeyboardThinkingOrbPreset.activeFrameInterval
                previousDate = date
                stepEngine(dt: dt)
            }
        }
        .overlay {
            if mode == .idle {
                Image(systemName: "mic.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
                    .frame(width: 30, height: 30)
                    .background(
                        Circle()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.92) : Color.black.opacity(0.86))
                    )
                    .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 1.0), value: mode == .idle)
        .onAppear {
            engine.setMode(mode)
            previousDate = .now
            stepEngine(dt: KeyboardThinkingOrbPreset.activeFrameInterval)
        }
        .onChange(of: mode) { _, newMode in
            engine.setMode(newMode)
        }
        .onChange(of: colorScheme) { _, _ in
            stepEngine(dt: 0.001)
        }
        .onDisappear {
            previousDate = nil
        }
    }

    private func stepEngine(dt: Double) {
        let ink: SIMD3<Double> =
            colorScheme == .dark
            ? SIMD3(0.94, 0.94, 0.96)
            : SIMD3(0.08, 0.08, 0.10)
        let success: SIMD3<Double> =
            colorScheme == .dark
            ? SIMD3(0.24, 0.84, 0.48)
            : SIMD3(0.05, 0.56, 0.26)
        let error: SIMD3<Double> =
            colorScheme == .dark
            ? SIMD3(1.00, 0.36, 0.34)
            : SIMD3(0.86, 0.18, 0.18)

        frame = engine.step(
            dt: dt,
            canvasSize: CGSize(width: diameter, height: diameter),
            level: level,
            inkColor: ink,
            successColor: success,
            errorColor: error,
            reduceMotion: reduceMotion
        )
    }
}
