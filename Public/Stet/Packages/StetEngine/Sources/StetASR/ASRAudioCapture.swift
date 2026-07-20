@preconcurrency import AVFoundation
import Foundation
import os

nonisolated struct ASRAudioFrame: Sendable, Equatable {
    static let sampleRate: Double = 16_000

    let samples: [Float]
    let level: Float

    init(samples: [Float], level: Float) {
        self.samples = samples
        self.level = min(max(level, 0), 1)
    }
}

nonisolated enum ASRAudioCaptureError: Error, LocalizedError, Sendable, Equatable {
    case audioUnavailable
    case consumerAlreadyActive

    var errorDescription: String? {
        switch self {
        case .audioUnavailable:
            "Audio input is unavailable."
        case .consumerAlreadyActive:
            "Another speech recognizer is already consuming audio."
        }
    }
}

typealias ASRAudioFrameHandler =
    @Sendable (Result<ASRAudioFrame, ASRAudioCaptureError>) -> Void

nonisolated protocol ASRAudioCapturing: AnyObject, Sendable {
    func prepare() async throws
    func start(handler: @escaping ASRAudioFrameHandler) async throws
    func stop()
    func reset() async throws
    func teardown()
}

nonisolated enum ASRAudioInputStrategy: String, Sendable {
    case builtInPreferred
    case airPodsHighQuality

    #if os(iOS)
        var categoryOptions: AVAudioSession.CategoryOptions {
            switch self {
            case .builtInPreferred:
                return [
                    .mixWithOthers,
                    .allowBluetoothA2DP,
                ]
            case .airPodsHighQuality:
                var options: AVAudioSession.CategoryOptions = [
                    .mixWithOthers,
                    .allowBluetoothHFP,
                ]
                if #available(iOS 26.0, *) {
                    options.insert(.bluetoothHighQualityRecording)
                }
                return options
            }
        }
    #endif

    func resolve(actualInputPortTypes: [String]) -> ASRAudioRouteResolution {
        let preferredPortType: String
        switch self {
        case .builtInPreferred:
            #if os(iOS)
                preferredPortType = AVAudioSession.Port.builtInMic.rawValue
            #else
                preferredPortType = "BuiltInMic"
            #endif
        case .airPodsHighQuality:
            #if os(iOS)
                preferredPortType = AVAudioSession.Port.bluetoothHFP.rawValue
            #else
                preferredPortType = "BluetoothHFP"
            #endif
        }

        if actualInputPortTypes.contains(preferredPortType) {
            return .preferredInputActive
        }
        return .systemFallback(actualInputPortTypes: actualInputPortTypes)
    }
}

nonisolated enum ASRAudioRouteResolution: Sendable, Equatable {
    case preferredInputActive
    case systemFallback(actualInputPortTypes: [String])

    var logValue: String {
        switch self {
        case .preferredInputActive:
            "preferred_input_active"
        case .systemFallback:
            "system_fallback"
        }
    }
}

nonisolated protocol ASRAudioCaptureHardware: AnyObject, Sendable {
    var isRunning: Bool { get }

    func prepare(frameHandler: @escaping ASRAudioFrameHandler) async throws
        -> ASRAudioRouteResolution
    func rebuild(frameHandler: @escaping ASRAudioFrameHandler) async throws
        -> ASRAudioRouteResolution
    func teardown()
}

nonisolated private final class ASRAudioFrameGate: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: ASRAudioFrameHandler?

    func open(handler: @escaping ASRAudioFrameHandler) throws {
        try lock.withLock {
            guard self.handler == nil else {
                throw ASRAudioCaptureError.consumerAlreadyActive
            }
            self.handler = handler
        }
    }

    func close() {
        lock.withLock {
            handler = nil
        }
    }

    func send(_ result: Result<ASRAudioFrame, ASRAudioCaptureError>) {
        let handler: ASRAudioFrameHandler? = lock.withLock { self.handler }
        handler?(result)
    }
}

nonisolated final class PersistentASRAudioCapture: ASRAudioCapturing, @unchecked Sendable {
    private struct RouteRecoveryState {
        var generation: UInt = 0
        var isRecovering = false
        var needsAnotherPass = false
        var task: Task<Void, Never>?
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.openwhispr.Stet",
        category: "ASRAudioCapture"
    )

    private let strategy: ASRAudioInputStrategy
    private let hardware: any ASRAudioCaptureHardware
    private let frameGate = ASRAudioFrameGate()
    private let notificationCenter: NotificationCenter
    private let routeRecoveryLock = NSLock()
    private var routeRecoveryState = RouteRecoveryState()
    private let observerLock = NSLock()
    private var routeChangeObserver: NSObjectProtocol?

    init(
        strategy: ASRAudioInputStrategy,
        notificationCenter: NotificationCenter = .default
    ) {
        self.strategy = strategy
        self.notificationCenter = notificationCenter
        self.hardware = AVAudioEngineASRAudioCaptureHardware(strategy: strategy)
    }

    init(
        strategy: ASRAudioInputStrategy,
        hardware: any ASRAudioCaptureHardware,
        notificationCenter: NotificationCenter = .default
    ) {
        self.strategy = strategy
        self.hardware = hardware
        self.notificationCenter = notificationCenter
    }

    func prepare() async throws {
        let resolution = try await hardware.prepare(frameHandler: makeFrameHandler())
        registerRouteChangeObserver()
        logResolution(resolution, event: "capture_prepared")
    }

    func start(handler: @escaping ASRAudioFrameHandler) async throws {
        if !hardware.isRunning {
            try await prepare()
        }
        guard hardware.isRunning else {
            throw ASRAudioCaptureError.audioUnavailable
        }
        try frameGate.open(handler: handler)
        Self.logger.info(
            "event=frame_gate_opened strategy=\(self.strategy.rawValue, privacy: .public)"
        )
    }

    func stop() {
        frameGate.close()
        Self.logger.info(
            "event=frame_gate_closed strategy=\(self.strategy.rawValue, privacy: .public) hardware_running=\(self.hardware.isRunning, privacy: .public)"
        )
    }

    func reset() async throws {
        let resolution = try await hardware.rebuild(frameHandler: makeFrameHandler())
        registerRouteChangeObserver()
        logResolution(resolution, event: "capture_reset")
    }

    func teardown() {
        frameGate.close()
        unregisterRouteChangeObserver()
        let task = routeRecoveryLock.withLock { () -> Task<Void, Never>? in
            routeRecoveryState.generation &+= 1
            routeRecoveryState.isRecovering = false
            routeRecoveryState.needsAnotherPass = false
            defer { routeRecoveryState.task = nil }
            return routeRecoveryState.task
        }
        task?.cancel()
        hardware.teardown()
        Self.logger.info(
            "event=capture_torn_down strategy=\(self.strategy.rawValue, privacy: .public)"
        )
    }

    #if os(iOS)
        func receiveRouteChange(reason: AVAudioSession.RouteChangeReason) {
            switch reason {
            case .categoryChange, .override, .routeConfigurationChange:
                Self.logger.debug(
                    "event=route_change_ignored strategy=\(self.strategy.rawValue, privacy: .public) reason=\(String(describing: reason), privacy: .public)"
                )
            default:
                requestRouteRecovery(reason: reason)
            }
        }

        private func registerRouteChangeObserver() {
            observerLock.withLock {
                guard routeChangeObserver == nil else { return }
                routeChangeObserver = notificationCenter.addObserver(
                    forName: AVAudioSession.routeChangeNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] notification in
                    let rawReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
                    let reason = rawReason.flatMap(AVAudioSession.RouteChangeReason.init(rawValue:)) ?? .unknown
                    self?.receiveRouteChange(reason: reason)
                }
            }
        }
    #else
        private func registerRouteChangeObserver() {}
    #endif

    private func unregisterRouteChangeObserver() {
        let observer = observerLock.withLock { () -> NSObjectProtocol? in
            defer { routeChangeObserver = nil }
            return routeChangeObserver
        }
        if let observer {
            notificationCenter.removeObserver(observer)
        }
    }

    #if os(iOS)
        private func requestRouteRecovery(reason: AVAudioSession.RouteChangeReason) {
            let start = routeRecoveryLock.withLock { () -> (generation: UInt, shouldStart: Bool) in
                if routeRecoveryState.isRecovering {
                    routeRecoveryState.needsAnotherPass = true
                    return (routeRecoveryState.generation, false)
                }
                routeRecoveryState.isRecovering = true
                return (routeRecoveryState.generation, true)
            }
            guard start.shouldStart else {
                Self.logger.debug(
                    "event=route_recovery_coalesced strategy=\(self.strategy.rawValue, privacy: .public) reason=\(String(describing: reason), privacy: .public)"
                )
                return
            }

            Self.logger.info(
                "event=route_recovery_requested strategy=\(self.strategy.rawValue, privacy: .public) reason=\(String(describing: reason), privacy: .public)"
            )
            let task = Task { [weak self] in
                guard let self else { return }
                await self.drainRouteRecoveries(generation: start.generation)
            }
            routeRecoveryLock.withLock {
                guard routeRecoveryState.generation == start.generation,
                    routeRecoveryState.isRecovering
                else {
                    task.cancel()
                    return
                }
                routeRecoveryState.task = task
            }
        }

        private func drainRouteRecoveries(generation: UInt) async {
            while !Task.isCancelled {
                do {
                    let resolution = try await hardware.rebuild(frameHandler: makeFrameHandler())
                    logResolution(resolution, event: "route_recovery_completed")
                } catch is CancellationError {
                    break
                } catch {
                    Self.logger.error(
                        "event=route_recovery_failed strategy=\(self.strategy.rawValue, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                    )
                    frameGate.send(.failure(.audioUnavailable))
                }

                let shouldContinue = routeRecoveryLock.withLock { () -> Bool in
                    guard routeRecoveryState.generation == generation else { return false }
                    if routeRecoveryState.needsAnotherPass {
                        routeRecoveryState.needsAnotherPass = false
                        return true
                    }
                    routeRecoveryState.isRecovering = false
                    routeRecoveryState.task = nil
                    return false
                }
                if !shouldContinue { return }
            }

            routeRecoveryLock.withLock {
                guard routeRecoveryState.generation == generation else { return }
                routeRecoveryState.isRecovering = false
                routeRecoveryState.needsAnotherPass = false
                routeRecoveryState.task = nil
            }
        }
    #endif

    private func logResolution(_ resolution: ASRAudioRouteResolution, event: String) {
        let actualInputs: String
        switch resolution {
        case .preferredInputActive:
            actualInputs = "preferred"
        case .systemFallback(let actualInputPortTypes):
            actualInputs =
                actualInputPortTypes.isEmpty
                ? "none"
                : actualInputPortTypes.joined(separator: ",")
        }
        Self.logger.info(
            "event=\(event, privacy: .public) strategy=\(self.strategy.rawValue, privacy: .public) resolution=\(resolution.logValue, privacy: .public) actual_inputs=\(actualInputs, privacy: .public)"
        )
    }

    private func makeFrameHandler() -> ASRAudioFrameHandler {
        let frameGate = frameGate
        return { result in
            frameGate.send(result)
        }
    }
}

nonisolated private final class ASRConverterInputGate: @unchecked Sendable {
    private let lock = NSLock()
    private var hasProvidedInput = false

    func claimInput() -> Bool {
        lock.withLock {
            guard !hasProvidedInput else { return false }
            hasProvidedInput = true
            return true
        }
    }
}

nonisolated final class AVAudioEngineASRAudioCaptureHardware:
    ASRAudioCaptureHardware, @unchecked Sendable
{
    private struct State {
        var generation: UInt = 0
        var wantsActiveCapture = false
        var audioEngine: AVAudioEngine?
        var converter: AVAudioConverter?
        var frameHandler: ASRAudioFrameHandler?
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.openwhispr.Stet",
        category: "ASRAudioRoute"
    )

    private let strategy: ASRAudioInputStrategy
    private let outputFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: ASRAudioFrame.sampleRate,
        channels: 1,
        interleaved: false
    )
    private let lifecycleLock = NSLock()
    private let stateLock = NSLock()
    private var state = State()

    init(strategy: ASRAudioInputStrategy) {
        self.strategy = strategy
    }

    var isRunning: Bool {
        stateLock.withLock { state.audioEngine?.isRunning == true }
    }

    func prepare(frameHandler: @escaping ASRAudioFrameHandler) async throws
        -> ASRAudioRouteResolution
    {
        let generation = stateLock.withLock { () -> UInt in
            state.wantsActiveCapture = true
            return state.generation
        }
        let resolution = try await configureAudioRoute()
        try validateActivation(generation: generation)
        try Task.checkCancellation()
        try lifecycleLock.withLock {
            let shouldStart = try stateLock.withLock { () throws -> Bool in
                guard state.generation == generation else { throw CancellationError() }
                state.frameHandler = frameHandler
                return state.audioEngine?.isRunning != true
            }
            if shouldStart {
                try replaceEngine()
            }
        }
        return resolution
    }

    func rebuild(frameHandler: @escaping ASRAudioFrameHandler) async throws
        -> ASRAudioRouteResolution
    {
        let generation = stateLock.withLock { () -> UInt in
            state.wantsActiveCapture = true
            return state.generation
        }
        let resolution = try await configureAudioRoute()
        try validateActivation(generation: generation)
        try Task.checkCancellation()
        try lifecycleLock.withLock {
            try stateLock.withLock {
                guard state.generation == generation else { throw CancellationError() }
                state.frameHandler = frameHandler
            }
            try replaceEngine()
        }
        return resolution
    }

    func teardown() {
        lifecycleLock.withLock {
            let engine = stateLock.withLock { () -> AVAudioEngine? in
                state.generation &+= 1
                state.wantsActiveCapture = false
                state.frameHandler = nil
                return detachEngineLocked()
            }
            stop(engine)
        }
        deactivateAudioSessionIfUnwanted()
    }

    private func replaceEngine() throws {
        let previousEngine = stateLock.withLock { detachEngineLocked() }
        stop(previousEngine)
        guard outputFormat != nil else { throw ASRAudioCaptureError.audioUnavailable }

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw ASRAudioCaptureError.audioUnavailable
        }

        input.installTap(onBus: 0, bufferSize: 4_096, format: nil) { [weak self] buffer, _ in
            self?.handleInputBuffer(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            stop(engine)
            throw ASRAudioCaptureError.audioUnavailable
        }
        stateLock.withLock {
            state.audioEngine = engine
            state.converter = nil
        }
    }

    private func detachEngineLocked() -> AVAudioEngine? {
        let engine = state.audioEngine
        state.audioEngine = nil
        state.converter = nil
        return engine
    }

    private func stop(_ engine: AVAudioEngine?) {
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
    }

    private func validateActivation(generation: UInt) throws {
        try stateLock.withLock {
            guard state.generation == generation, state.wantsActiveCapture else {
                #if os(iOS)
                    if !state.wantsActiveCapture {
                        Self.deactivateAudioSession(strategy: strategy)
                    }
                #endif
                throw CancellationError()
            }
        }
    }

    private func deactivateAudioSessionIfUnwanted() {
        #if os(iOS)
            stateLock.withLock {
                guard !state.wantsActiveCapture else { return }
                Self.deactivateAudioSession(strategy: strategy)
            }
        #endif
    }

    private func handleInputBuffer(_ buffer: AVAudioPCMBuffer) {
        guard buffer.format.sampleRate > 0,
            buffer.format.channelCount > 0,
            let outputFormat,
            let converter = converter(for: buffer.format, outputFormat: outputFormat)
        else {
            report(.failure(.audioUnavailable))
            return
        }

        let inputGate = ASRConverterInputGate()
        let inputBlock: AVAudioConverterInputBlock = { _, status in
            guard inputGate.claimInput() else {
                status.pointee = .noDataNow
                return nil
            }
            status.pointee = .haveData
            return buffer
        }

        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
        guard
            let converted = AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity: capacity
            )
        else {
            report(.failure(.audioUnavailable))
            return
        }

        var conversionError: NSError?
        let conversionStatus = converter.convert(
            to: converted,
            error: &conversionError,
            withInputFrom: inputBlock
        )
        guard conversionStatus != .error,
            conversionError == nil,
            let channelData = converted.floatChannelData
        else {
            report(.failure(.audioUnavailable))
            return
        }

        let samples = Array(
            UnsafeBufferPointer(start: channelData[0], count: Int(converted.frameLength))
        )
        guard !samples.isEmpty else { return }

        let sumOfSquares = samples.reduce(Float.zero) { $0 + $1 * $1 }
        let level = min(sqrt(sumOfSquares / Float(samples.count)) * 15, 1)
        report(.success(ASRAudioFrame(samples: samples, level: level)))
    }

    private func converter(
        for inputFormat: AVAudioFormat,
        outputFormat: AVAudioFormat
    ) -> AVAudioConverter? {
        stateLock.withLock {
            if let converter = state.converter,
                Self.formatsMatch(converter.inputFormat, inputFormat)
            {
                return converter
            }
            let converter = AVAudioConverter(from: inputFormat, to: outputFormat)
            state.converter = converter
            return converter
        }
    }

    private static func formatsMatch(_ lhs: AVAudioFormat, _ rhs: AVAudioFormat) -> Bool {
        lhs.sampleRate == rhs.sampleRate
            && lhs.channelCount == rhs.channelCount
            && lhs.commonFormat == rhs.commonFormat
            && lhs.isInterleaved == rhs.isInterleaved
    }

    private func report(_ result: Result<ASRAudioFrame, ASRAudioCaptureError>) {
        let frameHandler = stateLock.withLock { state.frameHandler }
        frameHandler?(result)
    }

    private func configureAudioRoute() async throws -> ASRAudioRouteResolution {
        #if os(iOS)
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: strategy.categoryOptions
            )
            try await Self.activateAudioSession(session)

            var requestedInput = "system"
            if strategy == .builtInPreferred {
                let builtInInput = session.availableInputs?.first {
                    $0.portType == .builtInMic
                }
                requestedInput = builtInInput?.portName ?? "built_in_unavailable"
                if let builtInInput {
                    do {
                        try session.setPreferredInput(builtInInput)
                    } catch {
                        Self.logger.error(
                            "event=preferred_input_request_failed strategy=\(self.strategy.rawValue, privacy: .public) requested_input=\(requestedInput, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                        )
                    }
                }
            }

            let actualInputPortTypes = session.currentRoute.inputs.map(\.portType.rawValue)
            let resolution = strategy.resolve(actualInputPortTypes: actualInputPortTypes)
            logAudioRoute(
                session,
                requestedInput: requestedInput,
                resolution: resolution
            )
            return resolution
        #else
            return .preferredInputActive
        #endif
    }

    #if os(iOS)
        private static func deactivateAudioSession(strategy: ASRAudioInputStrategy) {
            do {
                try AVAudioSession.sharedInstance().setActive(
                    false,
                    options: [.notifyOthersOnDeactivation]
                )
            } catch {
                Self.logger.error(
                    "event=audio_session_deactivation_failed strategy=\(strategy.rawValue, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                )
            }
        }

        private func logAudioRoute(
            _ session: AVAudioSession,
            requestedInput: String,
            resolution: ASRAudioRouteResolution
        ) {
            let input = session.currentRoute.inputs.first
            let output = session.currentRoute.outputs.first
            let inputName = input?.portName ?? "none"
            let inputType = input?.portType.rawValue ?? "none"
            let outputName = output?.portName ?? "none"
            let outputType = output?.portType.rawValue ?? "none"

            if #available(iOS 26.0, *) {
                let highQualityRecording =
                    input?.bluetoothMicrophoneExtension?.highQualityRecording
                Self.logger.info(
                    """
                    event=audio_route_resolved \
                    strategy=\(self.strategy.rawValue, privacy: .public) \
                    requested_input=\(requestedInput, privacy: .public) \
                    resolution=\(resolution.logValue, privacy: .public) \
                    input=\(inputName, privacy: .public) \
                    input_type=\(inputType, privacy: .public) \
                    output=\(outputName, privacy: .public) \
                    output_type=\(outputType, privacy: .public) \
                    sample_rate=\(session.sampleRate, privacy: .public) \
                    hq_supported=\(highQualityRecording?.isSupported == true, privacy: .public) \
                    hq_enabled=\(highQualityRecording?.isEnabled == true, privacy: .public)
                    """
                )
            } else {
                Self.logger.info(
                    """
                    event=audio_route_resolved \
                    strategy=\(self.strategy.rawValue, privacy: .public) \
                    requested_input=\(requestedInput, privacy: .public) \
                    resolution=\(resolution.logValue, privacy: .public) \
                    input=\(inputName, privacy: .public) \
                    input_type=\(inputType, privacy: .public) \
                    output=\(outputName, privacy: .public) \
                    output_type=\(outputType, privacy: .public) \
                    sample_rate=\(session.sampleRate, privacy: .public) \
                    hq_supported=false hq_enabled=false
                    """
                )
            }
        }

        private static func activateAudioSession(
            _ session: AVAudioSession = .sharedInstance()
        ) async throws {
            try await Task { @concurrent in
                try session.setActive(true)
            }.value
        }
    #endif
}
