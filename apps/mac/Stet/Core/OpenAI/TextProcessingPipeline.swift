import Foundation

struct TextProcessingStage: Sendable {
    let name: String
    let run: @Sendable (String) async throws -> String
}

struct TextProcessingPipeline: Sendable {
    let stages: [TextProcessingStage]

    func run(_ input: String) async throws -> String {
        var workingText = input
        for stage in stages {
            workingText = try await stage.run(workingText)
        }
        return workingText
    }
}
