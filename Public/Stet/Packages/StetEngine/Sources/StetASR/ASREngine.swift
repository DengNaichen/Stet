import Foundation

nonisolated public struct ASRResult: Sendable {
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

nonisolated public struct ASRMetrics: Sendable {
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

    /// Idempotent setup for long-lived resources such as the audio session and engine.
    /// Per-session resources, including recognition models, may be loaded lazily by
    /// `start(sessionId:)`.
    func prepare() async throws

    /// Begin a recording session. Assumes `prepare()` has already run; will lazy-prepare otherwise.
    func start(sessionId: String) async throws

    /// End the current recording session and finalize any pending recognition work.
    /// Long-lived audio resources remain prepared for the next session.
    func stop()

    /// Rebuild audio resources after the system media services process resets.
    func resetAudio() async throws

    /// Fully release resources: stop audio engine, finish result stream, drop models.
    func teardown()
}

public extension ASREngine {
    func resetAudio() async throws {
        try await prepare()
    }
}
