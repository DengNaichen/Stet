#if os(macOS)
    import Foundation
    import Testing
    import StetAI
    import StetCore

    @testable import Stet

    @MainActor
    struct RewriteModelCatalogStoreTests {
        private func data(revision: Int, enabled: Bool = true, model: String = "model-a") throws -> Data {
            try JSONEncoder().encode(
                RewriteModelCatalog(
                    schemaVersion: 1,
                    revision: revision,
                    providers: [
                        RewriteProviderCatalog(
                            id: DictationProvider.openAI.rawValue,
                            enabled: enabled,
                            defaultModelID: model,
                            models: [RewriteModelDescriptor(id: model, displayName: "Model A", enabled: true)]
                        )
                    ]
                ))
        }

        @Test func refreshUsesNewerCatalogAndPersistsIt() async throws {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let cache = directory.appendingPathComponent("catalog.json")
            let store = RewriteModelCatalogStore(
                bundledData: try data(revision: 1), cacheURL: cache,
                fetch: { try self.data(revision: 2, model: "model-b") })

            await store.refresh()

            #expect(store.revision == 2)
            #expect(store.catalog.resolvedModelID(for: .openAI, preferredID: nil) == "model-b")
            let relaunched = RewriteModelCatalogStore(bundledData: try data(revision: 1), cacheURL: cache)
            #expect(relaunched.revision == 2)
        }

        @Test func unavailablePreferredModelFallsBackWithoutChangingPreference() throws {
            let catalog = try RewriteModelCatalog.decode(try data(revision: 1, model: "new-default"))
            #expect(catalog.resolvedModelID(for: .openAI, preferredID: "old-model") == "new-default")
            #expect(catalog.resolvedModelID(for: .openAI, preferredID: "new-default") == "new-default")
        }

        @Test func invalidAndStaleUpdatesRetainCurrentCatalog() async throws {
            for remote in [Data("invalid".utf8), try data(revision: 1, model: "changed")] {
                let store = RewriteModelCatalogStore(
                    bundledData: try data(revision: 1), fetch: { remote })
                await store.refresh()
                #expect(store.revision == 1)
                #expect(store.catalog.resolvedModelID(for: .openAI, preferredID: nil) == "model-a")
            }
        }

        @Test func settingsTemporarilyFallsBackWithoutOverwritingSavedChoice() throws {
            let defaults = TestSupport.makeUserDefaults()
            let catalog = try RewriteModelCatalog.decode(try data(revision: 1, model: "new-default"))
            let settings = DictationSettingsStore(
                defaults: defaults, secretStore: TestSecretStore(),
                rewriteModelCatalog: RewriteModelCatalogSource(catalog))
            settings.saveRewriteProvider(.openAI)
            settings.saveSelectedModelID("old-model", for: .openAI)
            try settings.saveAPIKey("secret", for: .openAI)

            let snapshot = settings.loadSnapshot()

            #expect(snapshot.selectedModelID == "old-model")
            #expect(snapshot.resolvedModelID == "new-default")
            #expect(snapshot.rewriteProviderConfiguration?.model == "new-default")
            #expect(settings.loadSelectedModelID(for: .openAI) == "old-model")
        }

        @Test func disabledProviderHasNoModelsOrResolution() throws {
            let catalog = try RewriteModelCatalog.decode(try data(revision: 1, enabled: false))
            #expect(catalog.availableModels(for: .openAI).isEmpty)
            #expect(catalog.resolvedModelID(for: .openAI, preferredID: "model-a") == nil)
        }
    }
#endif
