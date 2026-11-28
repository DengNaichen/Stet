#if os(macOS)
    import Foundation
    import Testing
    import StetAI
    import StetCore

    @testable import Stet

    @MainActor
    struct RewriteModelCatalogStoreTests {
        @Test func settingsTemporarilyFallsBackWithoutOverwritingSavedChoice() throws {
            let defaults = TestSupport.makeUserDefaults()
            let catalog = RewriteModelCatalog.bundled
            let defaultModel = try #require(catalog.provider(.openAI)?.defaultModelID)
            let settings = DictationSettingsStore(
                defaults: defaults, secretStore: TestSecretStore(),
                rewriteModelCatalog: RewriteModelCatalogSource(catalog))
            settings.saveRewriteProvider(.openAI)
            settings.saveSelectedModelID("old-model", for: .openAI)
            try settings.saveAPIKey("secret", for: .openAI)

            let snapshot = settings.loadSnapshot()

            #expect(snapshot.selectedModelID == "old-model")
            #expect(snapshot.resolvedModelID == defaultModel)
            #expect(snapshot.rewriteProviderConfiguration?.model == defaultModel)
            #expect(settings.loadSelectedModelID(for: .openAI) == "old-model")
        }
    }
#endif
