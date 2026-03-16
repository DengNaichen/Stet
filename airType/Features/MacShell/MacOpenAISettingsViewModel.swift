#if os(macOS)
import Combine
import Foundation

@MainActor
final class MacOpenAISettingsViewModel: ObservableObject {
    static let defaultBaseURLString = "https://api.openai.com/v1"
    static let localRelayBaseURLString = "http://127.0.0.1:54321/functions/v1/relay/v1"

    @Published var apiKey = ""
    @Published private(set) var credentialMessage = "Stored securely in Keychain."
    @Published private(set) var credentialMessageIsError = false

    private let settingsStore: DictationSettingsStore

    init(settingsStore: DictationSettingsStore = DictationSettingsStore()) {
        self.settingsStore = settingsStore
    }

    var shouldHighlightMissingCredential: Bool {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func load() {
        apiKey = settingsStore.loadOpenAIAPIKey()
        credentialMessage = apiKey.isEmpty
            ? "Add a key or managed access token to enable cloud features."
            : "Credential is saved in Keychain."
        credentialMessageIsError = false
    }

    func saveCredential() {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            try settingsStore.saveOpenAIAPIKey(trimmedKey)
            apiKey = trimmedKey
            credentialMessage = trimmedKey.isEmpty
                ? "Credential removed from Keychain."
                : "Credential saved in Keychain."
            credentialMessageIsError = false
        } catch {
            credentialMessage = error.localizedDescription
            credentialMessageIsError = true
        }
    }

    func clearCredential() {
        apiKey = ""
        saveCredential()
    }
}
#endif
