import Foundation

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
