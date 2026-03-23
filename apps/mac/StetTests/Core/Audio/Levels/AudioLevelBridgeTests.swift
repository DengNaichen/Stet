import Testing

@testable import Stet

@MainActor
@Suite("Audio Level Bridge")
struct AudioLevelBridgeTests {
    @Test func emitsToMultipleStreams() async {
        let bridge = AudioLevelBridge()
        let streamA = bridge.makeStream()
        let streamB = bridge.makeStream()

        var iteratorA = streamA.makeAsyncIterator()
        var iteratorB = streamB.makeAsyncIterator()

        bridge.emit(0.25)

        let valueA = await iteratorA.next()
        let valueB = await iteratorB.next()

        #expect(valueA == 0.25)
        #expect(valueB == 0.25)
    }

    @Test func streamKeepsDeliveringLatestBufferedValues() async {
        let bridge = AudioLevelBridge()
        let stream = bridge.makeStream()
        var iterator = stream.makeAsyncIterator()

        bridge.emit(0.1)
        bridge.emit(0.2)
        bridge.emit(0.3)

        let firstValue = await iterator.next()

        bridge.emit(0.4)
        let secondValue = await iterator.next()

        #expect(firstValue == 0.3)
        #expect(secondValue == 0.4)
    }

    @Test func eachStreamReceivesItsOwnLatestValue() async {
        let bridge = AudioLevelBridge()
        let streamA = bridge.makeStream()
        let streamB = bridge.makeStream()

        var iteratorA = streamA.makeAsyncIterator()
        var iteratorB = streamB.makeAsyncIterator()

        bridge.emit(0.1)
        bridge.emit(0.6)

        let valueA = await iteratorA.next()
        let valueB = await iteratorB.next()

        #expect(valueA == 0.6)
        #expect(valueB == 0.6)
    }
}
