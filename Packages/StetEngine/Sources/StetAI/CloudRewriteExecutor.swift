import Foundation
import os
import StetCore
import StetRewrite

public enum CloudRewriteServiceFactory {
    public static func make(
        configuration: RewriteProviderConfiguration,
        session: URLSession,
        appleIntelligence: () -> any TextRewriteService = {
            UnavailableRewriteService(message: "Apple Intelligence is unavailable.")
        }
    ) -> any TextRewriteService {
        switch configuration.backend {
        case .appleIntelligence: return appleIntelligence()
        case .google(let key):
            return GoogleRewriteService(
                apiKey: key, model: configuration.model,
                thinkingLevel: configuration.thinkingLevel, session: session)
        case .anthropic(let key):
            return AnthropicRewriteService(apiKey: key, model: configuration.model, session: session)
        case .remote: return OpenAIRewriteService(configuration: configuration, session: session)
        }
    }
}

public struct CloudRewriteOutcome: Sendable {
    public let text: String
    public let didRewrite: Bool
    public let durationMs: Int
    public let provider: DictationProvider
    public let model: String
    public let thinkingLevel: RewriteThinkingLevel?
    public let error: (any Error)?
}

public struct CloudRewriteExecutor: Sendable {
    public typealias Factory = @Sendable (RewriteProviderConfiguration, URLSession) -> any TextRewriteService
    private static let logger = Logger(subsystem: "NaichengDeng.Stet", category: "Rewrite")
    private let session: URLSession
    private let makeService: Factory

    public init(
        session: URLSession = URLSession(configuration: .ephemeral),
        makeService: @escaping Factory = { CloudRewriteServiceFactory.make(configuration: $0, session: $1) }
    ) {
        self.session = session
        self.makeService = makeService
    }

    public func prewarm(configuration: RewriteProviderConfiguration, request: TextRewriteRequest) async {
        await makeService(configuration, session).prewarm(request)
    }

    public func execute(configuration: RewriteProviderConfiguration, request: TextRewriteRequest) async
        -> CloudRewriteOutcome
    {
        let start = ProcessInfo.processInfo.systemUptime
        let text: String
        let failure: (any Error)?
        do {
            text = try await makeService(configuration, session).rewrite(request)
            failure = nil
        } catch {
            text = request.text
            failure = error
        }
        let durationMs = Int(((ProcessInfo.processInfo.systemUptime - start) * 1000).rounded())
        let model = request.model ?? configuration.model
        Self.logger.info(
            "Rewrite provider=\(configuration.provider.rawValue, privacy: .public) model=\(model, privacy: .public) thinkingLevel=\(configuration.thinkingLevel?.rawValue ?? "none", privacy: .public) durationMs=\(durationMs) success=\(failure == nil)"
        )
        return CloudRewriteOutcome(
            text: text, didRewrite: failure == nil, durationMs: durationMs,
            provider: configuration.provider, model: model,
            thinkingLevel: configuration.thinkingLevel, error: failure)
    }
}
