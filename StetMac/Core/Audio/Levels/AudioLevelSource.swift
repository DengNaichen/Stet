import Foundation

nonisolated protocol AudioLevelSource: Sendable {
    func makeAudioLevelStream() async -> AsyncStream<Double>
}
