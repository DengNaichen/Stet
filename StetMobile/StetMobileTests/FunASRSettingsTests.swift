import Foundation
import Testing
@testable import StetMobile

@MainActor
struct FunASRSettingsTests {
    @Test func defaultsToBeijingAndPersistsRegionAndWorkspace() {
        let isolatedDefaults = makeDefaults()
        defer { isolatedDefaults.clear() }
        let defaults = isolatedDefaults.value
        let credentials = TestFunASRCredentialStore()

        let store = FunASRSettingsStore(defaults: defaults, credentialStore: credentials)
        #expect(store.region == .beijing)

        store.region = .singapore
        store.workspaceID = "workspace-123"

        let restored = FunASRSettingsStore(defaults: defaults, credentialStore: credentials)
        #expect(restored.region == .singapore)
        #expect(restored.workspaceID == "workspace-123")
    }

    @Test(arguments: ["dictation.engine", "dictation.localModel"])
    func newAndRetiredSelectionsResolveToRealtime(selectionKey: String) {
        let isolatedDefaults = makeDefaults()
        defer { isolatedDefaults.clear() }
        let defaults = isolatedDefaults.value
        defaults.set("whisperLargeV3Turbo", forKey: selectionKey)

        let store = MobileDictationSettingsStore(defaults: defaults)

        #expect(store.selectedEngine == .funASRRealtime)
        #expect(defaults.string(forKey: "dictation.engine") == "funASRRealtime")
        #expect(defaults.string(forKey: "dictation.localModel") == nil)
    }

    @Test func credentialStoreRoundTripFeedsConfiguration() throws {
        let isolatedDefaults = makeDefaults()
        defer { isolatedDefaults.clear() }
        let defaults = isolatedDefaults.value
        let credentials = TestFunASRCredentialStore()
        let store = FunASRSettingsStore(defaults: defaults, credentialStore: credentials)
        store.workspaceID = "workspace-123"

        try store.saveAPIKey("api-key")
        let configuration = try store.configuration()

        #expect(try store.loadAPIKey() == "api-key")
        #expect(configuration.apiKey == "api-key")
    }

    @Test func keychainCredentialRoundTrip() throws {
        let credentialStore = FunASRKeychainCredentialStore(
            service: "FunASRSettingsTests.\(UUID().uuidString)",
            account: "api-key"
        )
        defer { try? credentialStore.saveAPIKey("") }

        try credentialStore.saveAPIKey("first-key")
        #expect(try credentialStore.loadAPIKey() == "first-key")

        try credentialStore.saveAPIKey("updated-key")
        #expect(try credentialStore.loadAPIKey() == "updated-key")

        try credentialStore.saveAPIKey("")
        #expect(try credentialStore.loadAPIKey() == nil)
    }

    @Test func rejectsMissingAndInvalidConfiguration() {
        #expect(
            throws: FunASRConfigurationError.invalidWorkspaceID,
            performing: {
                _ = try FunASRConfiguration(
                    region: .beijing,
                    workspaceID: "workspace_bad",
                    apiKey: "api-key"
                )
            }
        )
        #expect(
            throws: FunASRConfigurationError.missingAPIKey,
            performing: {
                _ = try FunASRConfiguration(
                    region: .beijing,
                    workspaceID: "workspace-123",
                    apiKey: ""
                )
            }
        )
    }

    @Test func successfulValidationSavesTheKeyWithoutChangingSelectedEngine() async {
        let isolatedDefaults = makeDefaults()
        defer { isolatedDefaults.clear() }
        let defaults = isolatedDefaults.value
        let credentials = TestFunASRCredentialStore()
        let funSettings = FunASRSettingsStore(
            defaults: defaults,
            credentialStore: credentials
        )
        funSettings.workspaceID = "workspace-123"
        let dictationSettings = MobileDictationSettingsStore(defaults: defaults)
        dictationSettings.selectedEngine = .funASRRealtime
        let validator = TestFunASRConnectionValidator()
        let viewModel = RewriteSettingsViewModel(
            settingsStore: RewriteSettingsStore(),
            funASRSettingsStore: funSettings,
            funASRConnectionValidator: validator
        )
        viewModel.funASRAPIKeyInput = "api-key"

        await viewModel.validateFunASRConnection()

        #expect(viewModel.funASRValidationState == .success)
        #expect(dictationSettings.selectedEngine == .funASRRealtime)
        #expect(credentials.apiKey == "api-key")
        #expect(validator.validatedConfiguration?.workspaceID == "workspace-123")
    }

    @Test func authenticationFailureUsesASafeCredentialMessage() async {
        let isolatedDefaults = makeDefaults()
        defer { isolatedDefaults.clear() }
        let defaults = isolatedDefaults.value
        let funSettings = FunASRSettingsStore(
            defaults: defaults,
            credentialStore: TestFunASRCredentialStore()
        )
        funSettings.workspaceID = "workspace-123"
        let validator = TestFunASRConnectionValidator(error: .authenticationFailed)
        let viewModel = RewriteSettingsViewModel(
            settingsStore: RewriteSettingsStore(),
            funASRSettingsStore: funSettings,
            funASRConnectionValidator: validator
        )
        viewModel.funASRAPIKeyInput = "wrong-key"

        await viewModel.validateFunASRConnection()

        #expect(
            viewModel.funASRValidationState
                == .failed("FunASR authentication failed. Check the API key and Workspace ID.")
        )
    }

    private func makeDefaults() -> IsolatedDefaults {
        let suiteName = "FunASRSettingsTests.\(UUID().uuidString)"
        return IsolatedDefaults(
            value: UserDefaults(suiteName: suiteName)!,
            suiteName: suiteName
        )
    }
}

private struct IsolatedDefaults {
    let value: UserDefaults
    let suiteName: String

    func clear() {
        value.removePersistentDomain(forName: suiteName)
    }
}

@MainActor
private final class TestFunASRCredentialStore: FunASRCredentialStoring {
    var apiKey: String?

    func loadAPIKey() throws -> String? {
        apiKey
    }

    func saveAPIKey(_ apiKey: String) throws {
        self.apiKey = apiKey
    }
}

@MainActor
private final class TestFunASRConnectionValidator: FunASRConnectionValidating {
    private let error: FunASRError?
    private(set) var validatedConfiguration: FunASRConfiguration?

    init(error: FunASRError? = nil) {
        self.error = error
    }

    func validate(configuration: FunASRConfiguration) async throws {
        validatedConfiguration = configuration
        if let error {
            throw error
        }
    }
}
