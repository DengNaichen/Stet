import Foundation

protocol AudioLevelSource: Sendable {
    func makeAudioLevelStream() async -> AsyncStream<Double>
}
