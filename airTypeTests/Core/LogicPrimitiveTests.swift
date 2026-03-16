import Foundation
import Testing

@testable import airType

@MainActor
@Suite("Logic Primitives")
struct LogicPrimitiveTests {
    @Test func audioLevelBridgeEmitsToMultipleStreamsAndFinishes() async {
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

    @Test func textProcessingPipelineRunsStagesInOrder() async throws {
        let pipeline = TextProcessingPipeline(stages: [
            .init(name: "trim") { $0.trimmingCharacters(in: .whitespaces) },
            .init(name: "upper") { $0.uppercased() },
            .init(name: "suffix") { $0 + "!" },
        ])

        let result = try await pipeline.run(" hello ")

        #expect(result == "HELLO!")
    }

    @Test func textProcessingPipelineStopsOnFailure() async {
        let pipeline = TextProcessingPipeline(stages: [
            .init(name: "first") { _ in throw TestError.expected },
            .init(name: "second") { _ in "never" },
        ])

        await #expect(throws: TestError.expected) {
            try await pipeline.run("hello")
        }
    }

    @Test func networkProxySettingsHasCustomEndpointOnlyWhenComplete() {
        #expect(!NetworkProxySettings(mode: .custom, customScheme: .http, customHost: "", customPort: 8080).hasCustomEndpoint)
        #expect(!NetworkProxySettings(mode: .custom, customScheme: .http, customHost: "localhost", customPort: nil).hasCustomEndpoint)
        #expect(NetworkProxySettings(mode: .custom, customScheme: .http, customHost: "localhost", customPort: 8080).hasCustomEndpoint)
    }
}
