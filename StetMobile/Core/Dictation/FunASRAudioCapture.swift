@preconcurrency import AVFoundation
import Foundation

nonisolated struct FunASRAudioPacket: Sendable {
    let pcm16Data: Data
    let level: Float
}

nonisolated private final class FunASRConverterInputGate: @unchecked Sendable {
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

protocol FunASRAudioCapturing: AnyObject, Sendable {
    func prepare() async throws
    func start(
        handler: @escaping @Sendable (Result<FunASRAudioPacket, FunASRError>) -> Void
    ) async throws
    func stop()
    func reset() async throws
    func teardown()
}

nonisolated enum FunASRPCM16Encoder {
    static func encode(samples: [Float]) -> Data {
        var data = Data(capacity: samples.count * MemoryLayout<Int16>.size)
        for sample in samples {
            let clamped = max(-1, min(1, sample))
            let scaled: Int
            if clamped == -1 {
                scaled = Int(Int16.min)
            } else {
                scaled = Int((clamped * Float(Int16.max)).rounded())
            }
            var value = Int16(max(Int(Int16.min), min(Int(Int16.max), scaled))).littleEndian
            withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
        }
        return data
    }
}

nonisolated final class FunASRAudioFrameQueue: @unchecked Sendable {
    let frames: AsyncStream<Data>

    private let continuation: AsyncStream<Data>.Continuation
    private let lock = NSLock()
    private var tail = Data()
    private var isFinished = false

    init(maximumBufferedSeconds: Int = 5) {
        let maximumFrames = max(1, maximumBufferedSeconds * 10)
        (frames, continuation) = AsyncStream.makeStream(
            bufferingPolicy: .bufferingOldest(maximumFrames)
        )
    }

    func enqueue(_ pcmData: Data) throws {
        try lock.withLock {
            guard !isFinished else { return }
            tail.append(pcmData)
            while tail.count >= FunASRProtocol.audioFrameBytes {
                let frame = Data(tail.prefix(FunASRProtocol.audioFrameBytes))
                tail.removeFirst(FunASRProtocol.audioFrameBytes)
                try yield(frame)
            }
        }
    }

    func finish() throws {
        try lock.withLock {
            guard !isFinished else { return }
            isFinished = true
            if !tail.isEmpty {
                try yield(tail)
                tail.removeAll(keepingCapacity: false)
            }
            continuation.finish()
        }
    }

    func cancel() {
        lock.withLock {
            guard !isFinished else { return }
            isFinished = true
            tail.removeAll(keepingCapacity: false)
            continuation.finish()
        }
    }

    private func yield(_ data: Data) throws {
        switch continuation.yield(data) {
        case .enqueued:
            return
        case .dropped:
            throw FunASRError.audioQueueOverflow
        case .terminated:
            throw CancellationError()
        @unknown default:
            throw FunASRError.audioQueueOverflow
        }
    }
}

final class AVAudioEngineFunASRAudioCapture: FunASRAudioCapturing, @unchecked Sendable {
    private let outputFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: Double(FunASRProtocol.sampleRate),
        channels: 1,
        interleaved: false
    )
    private let lock = NSLock()

    private var audioEngine: AVAudioEngine?
    private var converter: AVAudioConverter?
    private var handler: (@Sendable (Result<FunASRAudioPacket, FunASRError>) -> Void)?
    private var routeChangeObserver: NSObjectProtocol?

    func prepare() async throws {
        #if os(iOS)
            try await Self.configureAudioSession()
        #endif
        try configureEngine()
        // iOS won't let a mixable recording session start for the first time after
        // the containing app has moved to the background. Keep RemoteIO warm while
        // this engine is selected, just like SenseVoice; `handler` still gates all
        // PCM processing until FunASR has acknowledged `task-started`.
        try startEngineIfNeeded()
        registerRouteChangeObserver()
    }

    func start(
        handler: @escaping @Sendable (Result<FunASRAudioPacket, FunASRError>) -> Void
    ) async throws {
        if audioEngine == nil {
            try await prepare()
        }
        // `prepare()` owns RemoteIO activation. A keyboard command can arrive after
        // the app has moved to the background, where iOS may reject a first start.
        // Starting a FunASR task therefore only opens the PCM gate.
        guard audioEngine?.isRunning == true else {
            throw FunASRError.audioUnavailable
        }
        lock.withLock { self.handler = handler }
    }

    func stop() {
        // Keep the already-authorized RemoteIO session alive for the next keyboard
        // request. No frames are processed or sent while the handler is nil.
        lock.withLock { handler = nil }
    }

    func reset() async throws {
        unregisterRouteChangeObserver()
        teardownAudioEngine()
        try await prepare()
    }

    func teardown() {
        unregisterRouteChangeObserver()
        teardownAudioEngine()
    }

    private func configureEngine() throws {
        guard audioEngine == nil, outputFormat != nil else { return }

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.channelCount > 0 else {
            throw FunASRError.audioUnavailable
        }

        audioEngine = engine
        converter = nil
        input.installTap(onBus: 0, bufferSize: 4_096, format: nil) { [weak self] buffer, _ in
            self?.handleInputBuffer(buffer)
        }
        engine.prepare()
    }

    private func startEngineIfNeeded() throws {
        guard let audioEngine, !audioEngine.isRunning else { return }
        audioEngine.prepare()
        try audioEngine.start()
    }

    private func teardownAudioEngine() {
        let engine = audioEngine
        audioEngine = nil
        lock.withLock {
            handler = nil
            converter = nil
        }
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
    }

    private func handleInputBuffer(_ buffer: AVAudioPCMBuffer) {
        guard lock.withLock({ handler != nil }),
            buffer.format.sampleRate > 0,
            buffer.format.channelCount > 0,
            let outputFormat,
            let converter = converter(for: buffer.format, outputFormat: outputFormat)
        else {
            report(.failure(.audioUnavailable))
            return
        }

        let inputGate = FunASRConverterInputGate()
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
        guard let converted = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
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
        report(
            .success(
                FunASRAudioPacket(
                    pcm16Data: FunASRPCM16Encoder.encode(samples: samples),
                    level: level
                )
            )
        )
    }

    private func report(_ result: Result<FunASRAudioPacket, FunASRError>) {
        lock.lock()
        let currentHandler = handler
        lock.unlock()
        currentHandler?(result)
    }

    private func converter(
        for inputFormat: AVAudioFormat,
        outputFormat: AVAudioFormat
    ) -> AVAudioConverter? {
        lock.withLock {
            if let converter,
                converter.inputFormat.sampleRate == inputFormat.sampleRate,
                converter.inputFormat.channelCount == inputFormat.channelCount,
                converter.inputFormat.commonFormat == inputFormat.commonFormat,
                converter.inputFormat.isInterleaved == inputFormat.isInterleaved
            {
                return converter
            }
            let newConverter = AVAudioConverter(from: inputFormat, to: outputFormat)
            converter = newConverter
            return newConverter
        }
    }

    private func registerRouteChangeObserver() {
        #if os(iOS)
            guard routeChangeObserver == nil else { return }
            routeChangeObserver = NotificationCenter.default.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.recoverFromRouteChange()
            }
        #endif
    }

    private func unregisterRouteChangeObserver() {
        guard let routeChangeObserver else { return }
        NotificationCenter.default.removeObserver(routeChangeObserver)
        self.routeChangeObserver = nil
    }

    private func recoverFromRouteChange() {
        #if os(iOS)
            guard let engine = audioEngine else { return }
            let input = engine.inputNode

            engine.stop()
            input.removeTap(onBus: 0)
            lock.withLock { converter = nil }
            input.installTap(onBus: 0, bufferSize: 4_096, format: nil) { [weak self] buffer, _ in
                self?.handleInputBuffer(buffer)
            }
            engine.prepare()

            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    try await Self.activateAudioSession()
                    guard self.audioEngine === engine else { return }
                    try self.startEngineIfNeeded()
                } catch {
                    self.report(.failure(.audioUnavailable))
                }
            }
        #endif
    }

    #if os(iOS)
        private nonisolated static func configureAudioSession() async throws {
            let session = AVAudioSession.sharedInstance()
            var options: AVAudioSession.CategoryOptions = [
                .mixWithOthers,
                .allowBluetoothHFP,
            ]
            if #available(iOS 26.0, *) {
                options.insert(.bluetoothHighQualityRecording)
            }
            try session.setCategory(.playAndRecord, mode: .default, options: options)
            try await activateAudioSession(session)
        }

        private nonisolated static func activateAudioSession(
            _ session: AVAudioSession = .sharedInstance()
        ) async throws {
            try await Task { @concurrent in
                try session.setActive(true)
            }.value
        }
    #endif
}
