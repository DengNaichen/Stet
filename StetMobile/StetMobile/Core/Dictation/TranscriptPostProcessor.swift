import StetCore
import StetRewrite

struct TranscriptPostProcessOutcome: Equatable, Sendable {
    let text: String
    let didRewrite: Bool
}

@MainActor
protocol TranscriptPostProcessing: AnyObject {
    var isAvailable: Bool { get }
    func prewarm()
    func process(_ transcript: String) async -> String
    func processWithOutcome(_ transcript: String) async -> TranscriptPostProcessOutcome
}

extension TranscriptPostProcessing {
    func prewarm() {}

    func processWithOutcome(_ transcript: String) async -> TranscriptPostProcessOutcome {
        let processed = await process(transcript)
        return TranscriptPostProcessOutcome(text: processed, didRewrite: isAvailable)
    }
}

@MainActor
final class SettingsTranscriptPostProcessor: TranscriptPostProcessing {
    private let settingsStore: RewriteSettingsStore
    private let dictionary: DictionaryModel

    init(
        settingsStore: RewriteSettingsStore,
        dictionary: DictionaryModel = DictionaryModel()
    ) {
        self.settingsStore = settingsStore
        self.dictionary = dictionary
    }

    var isAvailable: Bool {
        settingsStore.makeRewriteServiceIfEnabled() != nil
    }

    func prewarm() {
        guard let rewriteService = settingsStore.makeRewriteServiceIfEnabled() else {
            return
        }
        Task.detached(priority: .utility) {
            await rewriteService.prewarm(.cleanup("", audience: .human))
        }
    }

    func process(_ transcript: String) async -> String {
        await processWithOutcome(transcript).text
    }

    func processWithOutcome(_ transcript: String) async -> TranscriptPostProcessOutcome {
        guard let rewriteService = settingsStore.makeRewriteServiceIfEnabled() else {
            return TranscriptPostProcessOutcome(text: transcript, didRewrite: false)
        }

        let preferredSpellings = dictionary.loadIsEnabled() ? dictionary.loadEntries() : []
        do {
            let rewritten = try await rewriteService.rewrite(
                .cleanup(transcript, audience: .human, preferredSpellings: preferredSpellings)
            )
            return TranscriptPostProcessOutcome(text: rewritten, didRewrite: true)
        } catch {
            return TranscriptPostProcessOutcome(text: transcript, didRewrite: false)
        }
    }
}
