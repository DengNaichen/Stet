import StetCore
import StetRewrite

@MainActor
protocol TranscriptPostProcessing: AnyObject {
    var isAvailable: Bool { get }
    func prewarm()
    func process(_ transcript: String) async -> String
}

extension TranscriptPostProcessing {
    func prewarm() {}
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
        guard let rewriteService = settingsStore.makeRewriteServiceIfEnabled() else {
            return transcript
        }

        let preferredSpellings = dictionary.loadIsEnabled() ? dictionary.loadEntries() : []
        return
            (try? await rewriteService.rewrite(
                .cleanup(transcript, audience: .human, preferredSpellings: preferredSpellings)
            )) ?? transcript
    }
}
