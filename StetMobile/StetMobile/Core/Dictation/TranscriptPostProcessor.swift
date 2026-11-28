import StetAI
import StetCore
import StetRewrite

struct TranscriptPostProcessOutcome: Equatable, Sendable {
    let text: String
    let didRewrite: Bool
    var durationMs: Int? = nil
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
    private let executor: CloudRewriteExecutor
    private let dictionary: DictionaryModel

    init(
        settingsStore: RewriteSettingsStore,
        dictionary: DictionaryModel = DictionaryModel(),
        executor: CloudRewriteExecutor = CloudRewriteExecutor()
    ) {
        self.settingsStore = settingsStore
        self.dictionary = dictionary
        self.executor = executor
    }

    var isAvailable: Bool {
        settingsStore.configurationIfEnabled() != nil
    }

    func prewarm() {
        guard let configuration = settingsStore.configurationIfEnabled() else {
            return
        }
        Task(priority: .utility) { [executor] in
            await executor.prewarm(configuration: configuration, request: .cleanup("", audience: .human))
        }
    }

    func process(_ transcript: String) async -> String {
        await processWithOutcome(transcript).text
    }

    func processWithOutcome(_ transcript: String) async -> TranscriptPostProcessOutcome {
        guard let configuration = settingsStore.configurationIfEnabled() else {
            return TranscriptPostProcessOutcome(text: transcript, didRewrite: false)
        }

        let preferredSpellings = dictionary.loadIsEnabled() ? dictionary.loadEntries() : []
        let result = await executor.execute(
            configuration: configuration,
            request: .cleanup(transcript, audience: .human, preferredSpellings: preferredSpellings))
        return TranscriptPostProcessOutcome(
            text: result.text, didRewrite: result.didRewrite, durationMs: result.durationMs)
    }
}
