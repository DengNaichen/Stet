import Foundation

@MainActor
final class FunASRRealtimeEngine: @MainActor ASREngine, MobileASREngineFailureReporting {
    typealias ConfigurationProvider = @MainActor () throws -> FunASRConfiguration

    let name = "FunASR Realtime"
    let resultStream: AsyncStream<ASRResult>
    let failureStream: AsyncStream<MobileASREngineFailure>

    var onVolumeUpdate: ((Float) -> Void)?

    private let resultContinuation: AsyncStream<ASRResult>.Continuation
    private let failureContinuation: AsyncStream<MobileASREngineFailure>.Continuation
    private let configurationProvider: ConfigurationProvider
    private let audioCapture: any ASRAudioCapturing
    private let client: FunASRWebSocketClient
    private let startupBackgroundActivity: any FunASRStartupBackgroundActivityManaging

    private var activeSessionId: String?
    private var transcript = FunASRTranscriptAccumulator()
    private var audioQueue: FunASRAudioFrameQueue?
    private var audioByteCount = 0
    private var sessionStartedAt: TimeInterval?
    private var sendTask: Task<Void, Never>?
    private var receiveTask: Task<Void, Never>?
    private var stopTask: Task<Void, Never>?
    private var stopTimeoutTask: Task<Void, Never>?

    init(
        configurationProvider: @escaping ConfigurationProvider,
        audioCapture: (any ASRAudioCapturing)? = nil,
        transportFactory: FunASRWebSocketClient.TransportFactory? = nil,
        startupBackgroundActivity: (any FunASRStartupBackgroundActivityManaging)? = nil
    ) {
        self.configurationProvider = configurationProvider
        self.audioCapture =
            audioCapture ?? PersistentASRAudioCapture(strategy: .builtInPreferred)
        self.startupBackgroundActivity =
            startupBackgroundActivity ?? SystemFunASRStartupBackgroundActivityManager()
        self.client = FunASRWebSocketClient(
            transportFactory: transportFactory ?? {
                URLSessionFunASRWebSocketTransport()
            }
        )
        (resultStream, resultContinuation) = AsyncStream.makeStream()
        (failureStream, failureContinuation) = AsyncStream.makeStream()
    }

    func prepare() async throws {
        _ = try configurationProvider()
        try await audioCapture.prepare()
    }

    func start(sessionId: String) async throws {
        guard activeSessionId == nil else {
            throw FunASRError.serviceUnavailable
        }

        let configuration = try configurationProvider()
        startupBackgroundActivity.begin { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                await self.client.close()
            }
        }
        defer { startupBackgroundActivity.end() }

        do {
            try await withTaskCancellationHandler {
                try await client.beginTask(configuration: configuration)
            } onCancel: { [client] in
                Task { await client.close() }
            }
            try Task.checkCancellation()
        } catch {
            await client.close()
            throw error
        }

        let queue = FunASRAudioFrameQueue()
        activeSessionId = sessionId
        transcript = FunASRTranscriptAccumulator()
        audioQueue = queue
        audioByteCount = 0
        sessionStartedAt = ProcessInfo.processInfo.systemUptime
        startSending(queue: queue, sessionId: sessionId)
        startReceiving(sessionId: sessionId)

        do {
            try await audioCapture.start { [weak self, queue] result in
                switch result {
                case .success(let frame):
                    let pcm16Data = FunASRPCM16Encoder.encode(samples: frame.samples)
                    do {
                        try queue.enqueue(pcm16Data)
                        Task { @MainActor [weak self] in
                            guard let self, self.activeSessionId == sessionId else { return }
                            self.audioByteCount += pcm16Data.count
                            self.onVolumeUpdate?(frame.level)
                        }
                    } catch let error as FunASRError {
                        Task { @MainActor [weak self] in
                            await self?.handleRuntimeFailure(error, sessionId: sessionId)
                        }
                    } catch {
                        Task { @MainActor [weak self] in
                            await self?.handleRuntimeFailure(.audioQueueOverflow, sessionId: sessionId)
                        }
                    }
                case .failure:
                    Task { @MainActor [weak self] in
                        await self?.handleRuntimeFailure(.audioUnavailable, sessionId: sessionId)
                    }
                }
            }
        } catch {
            await abandonSession(sessionId: sessionId)
            if let error = error as? FunASRError {
                throw error
            }
            throw FunASRError.audioUnavailable
        }
    }

    func stop() {
        guard let sessionId = activeSessionId, stopTask == nil else { return }
        audioCapture.stop()
        do {
            try audioQueue?.finish()
        } catch let error as FunASRError {
            Task { @MainActor [weak self] in
                await self?.handleRuntimeFailure(error, sessionId: sessionId)
            }
            return
        } catch {
            Task { @MainActor [weak self] in
                await self?.handleRuntimeFailure(.audioQueueOverflow, sessionId: sessionId)
            }
            return
        }

        let pendingSendTask = sendTask
        stopTask = Task { @MainActor [weak self] in
            await pendingSendTask?.value
            guard let self, self.activeSessionId == sessionId, !Task.isCancelled else { return }
            do {
                try await self.client.finishTask()
            } catch let error as FunASRError {
                await self.handleRuntimeFailure(error, sessionId: sessionId)
                return
            } catch {
                await self.handleRuntimeFailure(.connectionFailed, sessionId: sessionId)
                return
            }
            self.startFinishTimeout(sessionId: sessionId)
        }
    }

    func resetAudio() async throws {
        try await audioCapture.reset()
    }

    func teardown() {
        startupBackgroundActivity.end()
        audioCapture.teardown()
        audioQueue?.cancel()
        sendTask?.cancel()
        receiveTask?.cancel()
        stopTask?.cancel()
        stopTimeoutTask?.cancel()
        activeSessionId = nil
        audioQueue = nil
        sendTask = nil
        receiveTask = nil
        stopTask = nil
        stopTimeoutTask = nil
        resultContinuation.finish()
        failureContinuation.finish()

        let client = client
        Task { await client.close() }
    }

    private func startSending(queue: FunASRAudioFrameQueue, sessionId: String) {
        let frames = queue.frames
        sendTask = Task { @MainActor [weak self] in
            do {
                for await frame in frames {
                    guard let self, self.activeSessionId == sessionId, !Task.isCancelled else {
                        return
                    }
                    try await self.client.sendAudio(frame)
                }
            } catch let error as FunASRError {
                await self?.handleRuntimeFailure(error, sessionId: sessionId)
            } catch is CancellationError {
                return
            } catch {
                await self?.handleRuntimeFailure(.connectionFailed, sessionId: sessionId)
            }
        }
    }

    private func startReceiving(sessionId: String) {
        receiveTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                while self.activeSessionId == sessionId, !Task.isCancelled {
                    switch try await self.client.receiveEvent() {
                    case .heartbeat:
                        continue
                    case .sentence(let sentence):
                        let text = self.transcript.update(with: sentence)
                        self.resultContinuation.yield(
                            ASRResult(sessionId: sessionId, text: text, isFinal: false)
                        )
                    case .taskFinished:
                        await self.client.markTaskFinished()
                        self.completeSession(sessionId: sessionId)
                        return
                    case .taskFailed(let error):
                        await self.handleRuntimeFailure(error, sessionId: sessionId)
                        return
                    case .taskStarted:
                        continue
                    }
                }
            } catch let error as FunASRError {
                await self.handleRuntimeFailure(error, sessionId: sessionId)
            } catch is CancellationError {
                return
            } catch {
                await self.handleRuntimeFailure(.connectionFailed, sessionId: sessionId)
            }
        }
    }

    private func startFinishTimeout(sessionId: String) {
        stopTimeoutTask?.cancel()
        stopTimeoutTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(15))
            } catch {
                return
            }
            await self?.handleRuntimeFailure(.taskFinishTimedOut, sessionId: sessionId)
        }
    }

    private func completeSession(sessionId: String) {
        guard activeSessionId == sessionId else { return }
        let wallDuration =
            sessionStartedAt.map {
                ProcessInfo.processInfo.systemUptime - $0
            } ?? 0
        let audioDuration = Double(audioByteCount) / 2 / Double(FunASRProtocol.sampleRate)

        audioCapture.stop()
        audioQueue?.cancel()
        stopTimeoutTask?.cancel()
        stopTask?.cancel()
        sendTask?.cancel()
        activeSessionId = nil
        audioQueue = nil
        sendTask = nil
        receiveTask = nil
        stopTask = nil
        stopTimeoutTask = nil

        resultContinuation.yield(
            ASRResult(
                sessionId: sessionId,
                text: transcript.text,
                isFinal: true,
                metrics: ASRMetrics(
                    audioDuration: audioDuration,
                    cpuDuration: 0,
                    wallDuration: wallDuration,
                    rtf: audioDuration > 0 ? wallDuration / audioDuration : 0
                )
            )
        )
    }

    private func abandonSession(sessionId: String) async {
        guard activeSessionId == sessionId else { return }
        audioCapture.stop()
        audioQueue?.cancel()
        sendTask?.cancel()
        receiveTask?.cancel()
        stopTask?.cancel()
        stopTimeoutTask?.cancel()
        activeSessionId = nil
        audioQueue = nil
        sendTask = nil
        receiveTask = nil
        stopTask = nil
        stopTimeoutTask = nil
        await client.close()
    }

    private func handleRuntimeFailure(_ error: FunASRError, sessionId: String) async {
        guard activeSessionId == sessionId else { return }
        await abandonSession(sessionId: sessionId)
        failureContinuation.yield(
            MobileASREngineFailure(
                sessionId: sessionId,
                message: error.localizedDescription
            )
        )
    }
}
