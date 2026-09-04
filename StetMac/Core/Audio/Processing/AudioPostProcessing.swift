import Foundation

protocol AudioPostProcessing: Sendable {
    func processAudioFile(at sourceURL: URL, duration: TimeInterval?) async throws -> AudioPostProcessingResult
}

struct AudioPostProcessingResult: Sendable {
    let url: URL
    let duration: TimeInterval?
    let cleanupURLs: [URL]
    let shouldDiscardAsNoSpeech: Bool

    nonisolated static func passthrough(url: URL, duration: TimeInterval?) -> Self {
        Self(
            url: url,
            duration: duration,
            cleanupURLs: [url],
            shouldDiscardAsNoSpeech: false
        )
    }

    nonisolated static func discard(url: URL, duration: TimeInterval?) -> Self {
        Self(
            url: url,
            duration: duration,
            cleanupURLs: [url],
            shouldDiscardAsNoSpeech: true
        )
    }

    nonisolated static func rewritten(
        sourceURL: URL,
        rewrittenURL: URL,
        duration: TimeInterval?
    ) -> Self {
        Self(
            url: rewrittenURL,
            duration: duration,
            cleanupURLs: [sourceURL, rewrittenURL],
            shouldDiscardAsNoSpeech: false
        )
    }
}
