import Foundation
import Metal
import MetalKit
import simd

struct DictationMetalEffectConfiguration {
    var size: CGSize
    var startDate: Date
    var frameInterval: Double
    var signals: MacDictationCapsuleVisualSignals
    var colors: (cottonFoam: SIMD3<Float>, waveTop: SIMD3<Float>, deepSea: SIMD3<Float>)
    var isPaused: Bool
}

final class DictationMetalEffectCoordinator {
    fileprivate var renderer: DictationMetalEffectRenderer?

    func makeView() -> MTKView {
        let view = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.framebufferOnly = false
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        view.preferredFramesPerSecond = 40
        view.enableSetNeedsDisplay = false
        view.isPaused = false

        if let device = view.device {
            renderer = DictationMetalEffectRenderer(device: device, view: view)
            view.delegate = renderer
        }

        return view
    }

    func update(view: MTKView, configuration: DictationMetalEffectConfiguration) {
        renderer?.update(configuration: configuration, view: view)
    }

    func dismantle(view: MTKView) {
        view.isPaused = true
        view.delegate = nil
        renderer = nil
    }
}

private final class StetVisualsMetalBundleToken {}

private struct AudioFieldComputeUniformsGPU {
    var deltaTime: Float
    var inputLevel: Float
    var padding: SIMD2<Float> = .zero
}

private struct AudioFieldSummaryGPU {
    var energy: Float
    var slowEnergy: Float
    var onset: Float
    var phase: Float
    var amplitude: Float
    var warp: Float
    var light: Float
    var padding: Float
}

private struct AudioFieldRenderUniformsGPU {
    var size: SIMD2<Float>
    var paddingTime: Float = 0
    var cottonFoam: SIMD3<Float>
    var padding0: Float = 0
    var waveTop: SIMD3<Float>
    var padding1: Float = 0
    var deepSea: SIMD3<Float>
    var padding2: Float = 0
}

private final class DictationMetalEffectRenderer: NSObject, MTKViewDelegate {
    private let commandQueue: MTLCommandQueue
    private let renderPipeline: MTLRenderPipelineState
    private let summaryPipeline: MTLComputePipelineState

    private let computeUniformBuffer: MTLBuffer
    private let renderUniformBuffer: MTLBuffer
    private let summaryBuffers: [MTLBuffer]
    private var summaryBufferIndex = 0

    private var configuration = DictationMetalEffectConfiguration(
        size: .zero,
        startDate: Date(),
        frameInterval: 1.0 / 40.0,
        signals: .zero,
        colors: (.zero, .zero, .zero),
        isPaused: false
    )
    private var lastKnownStartDate = Date.distantPast
    private var previousPaused = false
    private var lastFrameUptime: TimeInterval?

    init?(device: MTLDevice, view: MTKView) {
        assert(MemoryLayout<AudioFieldComputeUniformsGPU>.stride == 16)
        assert(MemoryLayout<AudioFieldSummaryGPU>.stride == 32)
        assert(MemoryLayout<AudioFieldRenderUniformsGPU>.stride == 112)

        guard let commandQueue = device.makeCommandQueue(),
            let library = try? device.makeDefaultLibrary(bundle: Self.shaderBundle),
            let renderPipeline = Self.makeRenderPipeline(device: device, library: library, view: view),
            let summaryPipeline = Self.makeComputePipeline(
                device: device, library: library, name: "audioFieldSummaryKernel"),
            let computeUniformBuffer = device.makeBuffer(
                length: MemoryLayout<AudioFieldComputeUniformsGPU>.stride,
                options: .storageModeShared
            ),
            let renderUniformBuffer = device.makeBuffer(
                length: MemoryLayout<AudioFieldRenderUniformsGPU>.stride,
                options: .storageModeShared
            ),
            let summaryA = device.makeBuffer(
                length: MemoryLayout<AudioFieldSummaryGPU>.stride,
                options: .storageModeShared
            ),
            let summaryB = device.makeBuffer(
                length: MemoryLayout<AudioFieldSummaryGPU>.stride,
                options: .storageModeShared
            )
        else {
            return nil
        }

        self.commandQueue = commandQueue
        self.renderPipeline = renderPipeline
        self.summaryPipeline = summaryPipeline
        self.computeUniformBuffer = computeUniformBuffer
        self.renderUniformBuffer = renderUniformBuffer
        self.summaryBuffers = [summaryA, summaryB]

        super.init()

        resetSummaryBuffers()
    }

    func update(configuration: DictationMetalEffectConfiguration, view: MTKView) {
        view.preferredFramesPerSecond = max(
            Int(round(1.0 / max(configuration.frameInterval, 1.0 / 120.0))),
            1
        )
        view.drawableSize = CGSize(
            width: max(configuration.size.width, 1) * displayScale(for: view),
            height: max(configuration.size.height, 1) * displayScale(for: view)
        )

        // Keep the listening configuration and its buffers untouched while paused.
        // Dictation resets its scalar level as it enters processing, but the final
        // presented listening frame must remain exactly as rendered.
        if configuration.isPaused {
            previousPaused = true
            lastFrameUptime = nil
            view.isPaused = true
            return
        }

        if previousPaused {
            lastFrameUptime = nil
        }
        previousPaused = false
        self.configuration = configuration
        view.isPaused = false

        if configuration.startDate != lastKnownStartDate {
            lastKnownStartDate = configuration.startDate
            lastFrameUptime = nil
            summaryBufferIndex = 0
            resetSummaryBuffers()
        }

        writeUniforms(deltaTime: 0)
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
            let renderPassDescriptor = view.currentRenderPassDescriptor,
            let commandBuffer = commandQueue.makeCommandBuffer()
        else {
            return
        }

        writeUniforms(deltaTime: nextFrameInterval())

        if let computeEncoder = commandBuffer.makeComputeCommandEncoder() {
            encodeSummary(into: computeEncoder)
            computeEncoder.endEncoding()
        }

        if let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
            renderEncoder.setRenderPipelineState(renderPipeline)
            renderEncoder.setFragmentBuffer(renderUniformBuffer, offset: 0, index: 0)
            renderEncoder.setFragmentBuffer(currentSummaryBuffer, offset: 0, index: 1)
            renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            renderEncoder.endEncoding()
        }

        commandBuffer.present(drawable)
        commandBuffer.commit()

        summaryBufferIndex = (summaryBufferIndex + 1) % 2
    }

    private func writeUniforms(deltaTime: Float) {
        let computePointer = computeUniformBuffer.contents().bindMemory(
            to: AudioFieldComputeUniformsGPU.self,
            capacity: 1
        )
        computePointer.pointee = AudioFieldComputeUniformsGPU(
            deltaTime: deltaTime,
            inputLevel: configuration.signals.estimatedSummary.level
        )

        let renderPointer = renderUniformBuffer.contents().bindMemory(
            to: AudioFieldRenderUniformsGPU.self,
            capacity: 1
        )
        renderPointer.pointee = AudioFieldRenderUniformsGPU(
            size: SIMD2<Float>(Float(configuration.size.width), Float(configuration.size.height)),
            cottonFoam: configuration.colors.cottonFoam,
            waveTop: configuration.colors.waveTop,
            deepSea: configuration.colors.deepSea
        )
    }

    private func encodeSummary(into encoder: MTLComputeCommandEncoder) {
        encoder.setComputePipelineState(summaryPipeline)
        encoder.setBuffer(computeUniformBuffer, offset: 0, index: 0)
        encoder.setBuffer(previousSummaryBuffer, offset: 0, index: 1)
        encoder.setBuffer(currentSummaryBuffer, offset: 0, index: 2)
        encoder.dispatchThreads(
            MTLSize(width: 1, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1)
        )
    }

    private func nextFrameInterval() -> Float {
        let now = ProcessInfo.processInfo.systemUptime
        defer { lastFrameUptime = now }
        guard let lastFrameUptime else {
            return Float(min(max(configuration.frameInterval, 0), 0.05))
        }
        return Float(min(max(now - lastFrameUptime, 0), 0.05))
    }

    private func resetSummaryBuffers() {
        let initialSummary = AudioFieldSummaryGPU(
            energy: 0,
            slowEnergy: 0,
            onset: 0,
            phase: 0,
            amplitude: 1.22,
            warp: 0,
            light: 0,
            padding: 0
        )
        for buffer in summaryBuffers {
            buffer.contents().bindMemory(to: AudioFieldSummaryGPU.self, capacity: 1).pointee = initialSummary
        }
    }

    private var currentSummaryBuffer: MTLBuffer {
        summaryBuffers[summaryBufferIndex]
    }

    private var previousSummaryBuffer: MTLBuffer {
        summaryBuffers[(summaryBufferIndex + 1) % 2]
    }

    private static func makeRenderPipeline(
        device: MTLDevice,
        library: MTLLibrary,
        view: MTKView
    ) -> MTLRenderPipelineState? {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        descriptor.vertexFunction = library.makeFunction(name: "audioReactiveOrbVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "audioReactiveOrbFragment")
        return try? device.makeRenderPipelineState(descriptor: descriptor)
    }

    private static func makeComputePipeline(
        device: MTLDevice,
        library: MTLLibrary,
        name: String
    ) -> MTLComputePipelineState? {
        guard let function = library.makeFunction(name: name) else { return nil }
        return try? device.makeComputePipelineState(function: function)
    }

    private func displayScale(for view: MTKView) -> CGFloat {
        #if os(macOS)
            view.window?.backingScaleFactor ?? 2
        #else
            view.window?.screen.scale ?? view.contentScaleFactor
        #endif
    }

    private static let shaderBundle: Bundle = {
        let frameworkBundle = Bundle(for: StetVisualsMetalBundleToken.self)
        if frameworkBundle.url(forResource: "default", withExtension: "metallib") != nil {
            return frameworkBundle
        }
        return .main
    }()
}
