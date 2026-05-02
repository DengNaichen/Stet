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

protocol ASREngine: AnyObject {
    var name: String { get }
    var resultStream: AsyncStream<ASRResult> { get }

    /// Idempotent one-time setup: configure audio session, load models, warm up audio engine.
    /// Per-session work belongs in `start(sessionId:)`.
    func prepare() async throws

    /// Begin a recording session. Assumes `prepare()` has already run; will lazy-prepare otherwise.
    func start(sessionId: String) async throws

    /// End the current recording session. The engine remains prepared for the next session.
    func stop()

    /// Fully release resources: stop audio engine, finish result stream, drop models.
    func teardown()
}
