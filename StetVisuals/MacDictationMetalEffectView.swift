#if os(macOS)
    import AppKit
    import Metal
    import MetalKit
    import SwiftUI
    import simd

    private struct MacDictationMetalEffectConfiguration {
        var size: CGSize
        var startDate: Date
        var frameInterval: Double
        var signals: MacDictationCapsuleVisualSignals
        var colors: (cottonFoam: SIMD3<Float>, waveTop: SIMD3<Float>, deepSea: SIMD3<Float>)
        var isPaused: Bool
        var fieldGain: Float
        var fieldBlurSigma: Float
        var gradientBlurSigma: Float
        var motionGain: Float
    }

    struct MacDictationMetalEffectView: NSViewRepresentable {
        let size: CGSize
        let startDate: Date
        let frameInterval: Double
        let signals: MacDictationCapsuleVisualSignals
        let colors: (cottonFoam: Color, waveTop: Color, deepSea: Color)
        let isPaused: Bool
        var fieldGain: Float = 1
        var fieldBlurSigma: Float = MacDictationAudioFieldConstants.fieldBlurSigma
        var gradientBlurSigma: Float = MacDictationAudioFieldConstants.gradientBlurSigma
        var motionGain: Float = 10

        func makeCoordinator() -> Coordinator {
            Coordinator()
        }

        func makeNSView(context: Context) -> MTKView {
            let view = context.coordinator.makeView()
            update(view, coordinator: context.coordinator)
            return view
        }

        func updateNSView(_ nsView: MTKView, context: Context) {
            update(nsView, coordinator: context.coordinator)
        }

        private func update(_ nsView: MTKView, coordinator: Coordinator) {
            let configuration = MacDictationMetalEffectConfiguration(
                size: size,
                startDate: startDate,
                frameInterval: frameInterval,
                signals: signals,
                colors: (
                    cottonFoam: colors.cottonFoam.simdRGB,
                    waveTop: colors.waveTop.simdRGB,
                    deepSea: colors.deepSea.simdRGB
                ),
                isPaused: isPaused,
                fieldGain: fieldGain,
                fieldBlurSigma: fieldBlurSigma,
                gradientBlurSigma: gradientBlurSigma,
                motionGain: motionGain
            )
            coordinator.renderer?.update(configuration: configuration, view: nsView)
        }

        final class Coordinator {
            fileprivate var renderer: MacDictationMetalEffectRenderer?

            func makeView() -> MTKView {
                let view = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
                view.framebufferOnly = false
                view.colorPixelFormat = .bgra8Unorm
                view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
                view.preferredFramesPerSecond = 40
                view.enableSetNeedsDisplay = false
                view.isPaused = false
                if let device = view.device {
                    renderer = MacDictationMetalEffectRenderer(device: device, view: view)
                    view.delegate = renderer
                }
                return view
            }
        }
    }

    private final class StetVisualsMetalBundleToken {}

    private struct AudioBandFeatureGPU {
        var position: SIMD2<Float>
        var weight: Float
        var padding: Float = 0
    }

    private struct AudioFieldComputeUniformsGPU {
        var gridSize: UInt32
        var bandCount: UInt32
        var sigmaX: Float
        var sigmaY: Float
        var fieldBlurSigma: Float
        var gradientBlurSigma: Float
        var fieldGain: Float
        var motionGain: Float
    }

    private struct AudioFieldSummaryGPU {
        var level: Float
        var flowX: Float
        var flowY: Float
        var padding: Float
        var groupedBands: SIMD4<Float>
    }

    private struct AudioFieldRenderUniformsGPU {
        var size: SIMD2<Float>
        var time: Float
        var motionGain: Float
        var cottonFoam: SIMD3<Float>
        var padding0: Float = 0
        var waveTop: SIMD3<Float>
        var padding1: Float = 0
        var deepSea: SIMD3<Float>
        var padding2: Float = 0
    }

    private final class MacDictationMetalEffectRenderer: NSObject, MTKViewDelegate {
        private let device: MTLDevice
        private let commandQueue: MTLCommandQueue
        private let renderPipeline: MTLRenderPipelineState
        private let splatPipeline: MTLComputePipelineState
        private let blurPipeline: MTLComputePipelineState
        private let gradientPipeline: MTLComputePipelineState
        private let summaryPipeline: MTLComputePipelineState

        private let featureBuffer: MTLBuffer
        private let computeUniformBuffer: MTLBuffer
        private let renderUniformBuffer: MTLBuffer
        private let summaryBuffers: [MTLBuffer]
        private var summaryBufferIndex = 0

        private let densityTexture: MTLTexture
        private let blurredTexture: MTLTexture
        private let gradientTexture: MTLTexture

        private var configuration = MacDictationMetalEffectConfiguration(
            size: .zero,
            startDate: Date(),
            frameInterval: 1.0 / 40.0,
            signals: .zero,
            colors: (.zero, .zero, .zero),
            isPaused: false,
            fieldGain: 1,
            fieldBlurSigma: MacDictationAudioFieldConstants.fieldBlurSigma,
            gradientBlurSigma: MacDictationAudioFieldConstants.gradientBlurSigma,
            motionGain: 10
        )
        private var lastKnownStartDate = Date.distantPast
        private var accumulatedPauseDuration: TimeInterval = 0
        private var pauseStartedAt: Date?
        private var previousPaused = false
        private var pausedElapsed: TimeInterval = 0

        init?(device: MTLDevice, view: MTKView) {
            guard let commandQueue = device.makeCommandQueue(),
                let library = try? device.makeDefaultLibrary(bundle: Self.shaderBundle),
                let renderPipeline = Self.makeRenderPipeline(device: device, library: library, view: view),
                let splatPipeline = Self.makeComputePipeline(
                    device: device, library: library, name: "audioFieldSplatKernel"),
                let blurPipeline = Self.makeComputePipeline(
                    device: device, library: library, name: "audioFieldBlurKernel"),
                let gradientPipeline = Self.makeComputePipeline(
                    device: device, library: library, name: "audioFieldGradientKernel"),
                let summaryPipeline = Self.makeComputePipeline(
                    device: device, library: library, name: "audioFieldSummaryKernel"),
                let featureBuffer = device.makeBuffer(
                    length: MemoryLayout<AudioBandFeatureGPU>.stride * MacDictationCapsuleVisualSignals.bandCount,
                    options: .storageModeShared
                ),
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
                ),
                let densityTexture = Self.makeTexture(device: device, pixelFormat: .r16Float),
                let blurredTexture = Self.makeTexture(device: device, pixelFormat: .r16Float),
                let gradientTexture = Self.makeTexture(device: device, pixelFormat: .rg16Float)
            else {
                return nil
            }

            self.device = device
            self.commandQueue = commandQueue
            self.renderPipeline = renderPipeline
            self.splatPipeline = splatPipeline
            self.blurPipeline = blurPipeline
            self.gradientPipeline = gradientPipeline
            self.summaryPipeline = summaryPipeline
            self.featureBuffer = featureBuffer
            self.computeUniformBuffer = computeUniformBuffer
            self.renderUniformBuffer = renderUniformBuffer
            self.summaryBuffers = [summaryA, summaryB]
            self.densityTexture = densityTexture
            self.blurredTexture = blurredTexture
            self.gradientTexture = gradientTexture

            super.init()

            memset(summaryA.contents(), 0, MemoryLayout<AudioFieldSummaryGPU>.stride)
            memset(summaryB.contents(), 0, MemoryLayout<AudioFieldSummaryGPU>.stride)
        }

        func update(configuration: MacDictationMetalEffectConfiguration, view: MTKView) {
            self.configuration = configuration
            view.preferredFramesPerSecond = max(Int(round(1.0 / max(configuration.frameInterval, 1.0 / 120.0))), 1)
            view.drawableSize = CGSize(
                width: max(configuration.size.width, 1) * (view.window?.backingScaleFactor ?? 2),
                height: max(configuration.size.height, 1) * (view.window?.backingScaleFactor ?? 2)
            )

            if configuration.startDate != lastKnownStartDate {
                lastKnownStartDate = configuration.startDate
                accumulatedPauseDuration = 0
                pauseStartedAt = nil
                pausedElapsed = 0
                summaryBufferIndex = 0
                memset(summaryBuffers[0].contents(), 0, MemoryLayout<AudioFieldSummaryGPU>.stride)
                memset(summaryBuffers[1].contents(), 0, MemoryLayout<AudioFieldSummaryGPU>.stride)
            }

            if configuration.isPaused, !previousPaused {
                pauseStartedAt = Date()
                pausedElapsed = currentElapsed(now: pauseStartedAt ?? Date())
            } else if !configuration.isPaused, previousPaused, let pauseStartedAt {
                accumulatedPauseDuration += Date().timeIntervalSince(pauseStartedAt)
                self.pauseStartedAt = nil
            }
            previousPaused = configuration.isPaused

            writeFeatureBuffer(signals: configuration.signals)
            writeUniforms()
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            guard let drawable = view.currentDrawable,
                let renderPassDescriptor = view.currentRenderPassDescriptor,
                let commandBuffer = commandQueue.makeCommandBuffer()
            else {
                return
            }

            writeUniforms()

            if let computeEncoder = commandBuffer.makeComputeCommandEncoder() {
                encodeSplat(into: computeEncoder)
                encodeBlur(into: computeEncoder)
                encodeGradient(into: computeEncoder)
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

        private func writeFeatureBuffer(signals: MacDictationCapsuleVisualSignals) {
            let pointer = featureBuffer.contents().bindMemory(
                to: AudioBandFeatureGPU.self,
                capacity: MacDictationCapsuleVisualSignals.bandCount
            )
            for index in 0..<MacDictationCapsuleVisualSignals.bandCount {
                let feature = signals.bands[index]
                pointer[index] = AudioBandFeatureGPU(
                    position: SIMD2<Float>(feature.x, feature.y),
                    weight: feature.weight
                )
            }
        }

        private func writeUniforms() {
            let computePointer = computeUniformBuffer.contents().bindMemory(
                to: AudioFieldComputeUniformsGPU.self,
                capacity: 1
            )
            computePointer.pointee = AudioFieldComputeUniformsGPU(
                gridSize: UInt32(MacDictationAudioFieldConstants.fieldGridSize),
                bandCount: UInt32(MacDictationCapsuleVisualSignals.bandCount),
                sigmaX: MacDictationAudioFieldConstants.fieldSigmaX,
                sigmaY: MacDictationAudioFieldConstants.fieldSigmaY,
                fieldBlurSigma: configuration.fieldBlurSigma,
                gradientBlurSigma: configuration.gradientBlurSigma,
                fieldGain: configuration.fieldGain,
                motionGain: configuration.motionGain
            )

            let renderPointer = renderUniformBuffer.contents().bindMemory(
                to: AudioFieldRenderUniformsGPU.self,
                capacity: 1
            )
            renderPointer.pointee = AudioFieldRenderUniformsGPU(
                size: SIMD2<Float>(Float(configuration.size.width), Float(configuration.size.height)),
                time: Float(configuration.isPaused ? pausedElapsed : currentElapsed(now: Date())),
                motionGain: configuration.motionGain,
                cottonFoam: configuration.colors.cottonFoam,
                waveTop: configuration.colors.waveTop,
                deepSea: configuration.colors.deepSea
            )
        }

        private func encodeSplat(into encoder: MTLComputeCommandEncoder) {
            encoder.setComputePipelineState(splatPipeline)
            encoder.setTexture(densityTexture, index: 0)
            encoder.setBuffer(featureBuffer, offset: 0, index: 0)
            encoder.setBuffer(computeUniformBuffer, offset: 0, index: 1)
            dispatch2D(pipeline: splatPipeline, encoder: encoder)
        }

        private func encodeBlur(into encoder: MTLComputeCommandEncoder) {
            encoder.setComputePipelineState(blurPipeline)
            encoder.setTexture(densityTexture, index: 0)
            encoder.setTexture(blurredTexture, index: 1)
            encoder.setBuffer(computeUniformBuffer, offset: 0, index: 1)
            dispatch2D(pipeline: blurPipeline, encoder: encoder)
        }

        private func encodeGradient(into encoder: MTLComputeCommandEncoder) {
            encoder.setComputePipelineState(gradientPipeline)
            encoder.setTexture(blurredTexture, index: 0)
            encoder.setTexture(gradientTexture, index: 1)
            encoder.setBuffer(computeUniformBuffer, offset: 0, index: 1)
            dispatch2D(pipeline: gradientPipeline, encoder: encoder)
        }

        private func encodeSummary(into encoder: MTLComputeCommandEncoder) {
            encoder.setComputePipelineState(summaryPipeline)
            encoder.setTexture(blurredTexture, index: 0)
            encoder.setTexture(gradientTexture, index: 1)
            encoder.setBuffer(featureBuffer, offset: 0, index: 0)
            encoder.setBuffer(computeUniformBuffer, offset: 0, index: 1)
            encoder.setBuffer(previousSummaryBuffer, offset: 0, index: 2)
            encoder.setBuffer(currentSummaryBuffer, offset: 0, index: 3)
            encoder.dispatchThreads(
                MTLSize(width: 1, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
        }

        private func dispatch2D(pipeline: MTLComputePipelineState, encoder: MTLComputeCommandEncoder) {
            let size = MTLSize(
                width: MacDictationAudioFieldConstants.fieldGridSize,
                height: MacDictationAudioFieldConstants.fieldGridSize,
                depth: 1
            )
            let threads = MTLSize(
                width: min(pipeline.threadExecutionWidth, MacDictationAudioFieldConstants.fieldGridSize),
                height: max(
                    1,
                    min(
                        pipeline.maxTotalThreadsPerThreadgroup / max(pipeline.threadExecutionWidth, 1),
                        MacDictationAudioFieldConstants.fieldGridSize)),
                depth: 1
            )
            encoder.dispatchThreads(size, threadsPerThreadgroup: threads)
        }

        private func currentElapsed(now: Date) -> TimeInterval {
            let pauseDuration =
                accumulatedPauseDuration
                + (configuration.isPaused ? now.timeIntervalSince(pauseStartedAt ?? now) : 0)
            return max(0, now.timeIntervalSince(configuration.startDate) - pauseDuration)
        }

        private var currentSummaryBuffer: MTLBuffer {
            summaryBuffers[summaryBufferIndex]
        }

        private var previousSummaryBuffer: MTLBuffer {
            summaryBuffers[(summaryBufferIndex + 1) % 2]
        }

        private static func makeTexture(device: MTLDevice, pixelFormat: MTLPixelFormat) -> MTLTexture? {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: pixelFormat,
                width: MacDictationAudioFieldConstants.fieldGridSize,
                height: MacDictationAudioFieldConstants.fieldGridSize,
                mipmapped: false
            )
            descriptor.usage = [.shaderRead, .shaderWrite]
            descriptor.storageMode = .private
            return device.makeTexture(descriptor: descriptor)
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

        private static let shaderBundle: Bundle = {
            let frameworkBundle = Bundle(for: StetVisualsMetalBundleToken.self)
            if frameworkBundle.url(forResource: "default", withExtension: "metallib") != nil {
                return frameworkBundle
            }
            return .main
        }()
    }

    private extension Color {
        var simdRGB: SIMD3<Float> {
            let nsColor = NSColor(self).usingColorSpace(.deviceRGB) ?? .white
            return SIMD3<Float>(
                Float(nsColor.redComponent),
                Float(nsColor.greenComponent),
                Float(nsColor.blueComponent)
            )
        }
    }
#endif
