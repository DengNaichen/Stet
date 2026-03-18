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
}
