import Foundation

public struct ASRResult: Sendable {
    public let sessionId: String
    public let text: String
    public let isFinal: Bool
    public let metrics: ASRMetrics?

    public init(
        sessionId: String,
        text: String,
        isFinal: Bool,
        metrics: ASRMetrics? = nil
    ) {
        self.sessionId = sessionId
        self.text = text
        self.isFinal = isFinal
        self.metrics = metrics
    }
}

public struct ASRMetrics: Sendable {
    public let audioDuration: Double
    public let cpuDuration: Double
    public let wallDuration: Double
    public let rtf: Double

    public init(audioDuration: Double, cpuDuration: Double, wallDuration: Double, rtf: Double) {
        self.audioDuration = audioDuration
        self.cpuDuration = cpuDuration
        self.wallDuration = wallDuration
        self.rtf = rtf
    }
}

public protocol ASREngine: AnyObject {
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
