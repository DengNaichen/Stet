import Testing

@testable import Stet

@MainActor
@Suite("Audio Level Bridge")
struct AudioLevelBridgeTests {
    @Test func emitsToMultipleStreamsAndFinishes() async {
        let bridge = AudioLevelBridge()
        let streamA = bridge.makeStream()
        let streamB = bridge.makeStream()

        bridge.emit(0.25)
        bridge.finish()

        var iteratorA = streamA.makeAsyncIterator()
        var iteratorB = streamB.makeAsyncIterator()

        let valueA = await iteratorA.next()
        let valueB = await iteratorB.next()
        let endA = await iteratorA.next()
        let endB = await iteratorB.next()

        #expect(valueA == 0.25)
        #expect(valueB == 0.25)
        #expect(endA == nil)
        #expect(endB == nil)
    }

    @Test func streamContinuesDeliveringValuesUntilExplicitFinish() async {
        let bridge = AudioLevelBridge()
        let stream = bridge.makeStream()
        var iterator = stream.makeAsyncIterator()

        bridge.emit(0.1)
        let firstValue = await iterator.next()

        bridge.emit(0)
        let silenceValue = await iterator.next()

        bridge.emit(0.4)
        let secondValue = await iterator.next()

        bridge.finish()
        let end = await iterator.next()

        #expect(firstValue == 0.1)
        #expect(silenceValue == 0)
        #expect(secondValue == 0.4)
        #expect(end == nil)
    }
}
