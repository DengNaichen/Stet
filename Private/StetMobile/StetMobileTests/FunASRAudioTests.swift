import Foundation
import Testing
@testable import StetMobile

struct FunASRAudioTests {
    @Test func encodesClampedPCM16LittleEndian() {
        let encoded = FunASRPCM16Encoder.encode(samples: [-2, 0, 0.5, 2])

        #expect(
            Array(encoded) == [
                0x00, 0x80,
                0x00, 0x00,
                0x00, 0x40,
                0xFF, 0x7F,
            ]
        )
    }

    @Test func framesAudioAt3200BytesAndFlushesTheTailInOrder() async throws {
        let queue = FunASRAudioFrameQueue()
        let source = Data((0..<6_401).map { UInt8($0 % 251) })

        try queue.enqueue(source)
        try queue.finish()

        var iterator = queue.frames.makeAsyncIterator()
        let first = try #require(await iterator.next())
        let second = try #require(await iterator.next())
        let tail = try #require(await iterator.next())

        #expect(first == source.subdata(in: 0..<3_200))
        #expect(second == source.subdata(in: 3_200..<6_400))
        #expect(tail == source.subdata(in: 6_400..<6_401))
        #expect(await iterator.next() == nil)
    }

    @Test func failsInsteadOfDroppingAudioWhenFiveSecondQueueOverflows() throws {
        let queue = FunASRAudioFrameQueue()
        let frame = Data(repeating: 1, count: FunASRProtocol.audioFrameBytes)

        for _ in 0..<50 {
            try queue.enqueue(frame)
        }

        do {
            try queue.enqueue(frame)
            Issue.record("Expected the bounded audio queue to reject overflow")
        } catch let error as FunASRError {
            #expect(error == .audioQueueOverflow)
        } catch {
            Issue.record("Expected FunASRError.audioQueueOverflow, got \(error)")
        }
    }
}
