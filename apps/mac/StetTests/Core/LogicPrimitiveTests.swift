import Foundation
import Testing

@testable import Stet

@MainActor
@Suite("Logic Primitives")
struct LogicPrimitiveTests {
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

}
