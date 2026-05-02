import Foundation

struct ASRResult {
    let text: String
    let isFinal: Bool
    let metrics: ASRMetrics?
}

struct ASRMetrics {
    let audioDuration: Double
    let cpuDuration: Double
    let wallDuration: Double
    let rtf: Double
}

protocol ASREngine {
    var name: String { get }
    var resultStream: AsyncStream<ASRResult> { get }
    func start(sessionId: String) async throws
    func stop()
}
