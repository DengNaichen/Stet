#if os(macOS)
    import Foundation
    import Testing

    @testable import Stet

    @MainActor
    struct AppCompatibilityStoreTests {
        private func data(_ revision: Int, _ identifiers: [String], schema: Int = 1) throws -> Data {
            try JSONEncoder().encode(
                AppCompatibilityStore.Configuration(schemaVersion: schema, revision: revision, bundleIDs: identifiers))
        }

        @Test func bundledListContainsExistingApplications() {
            let store = AppCompatibilityStore()
            #expect(store.contains("com.openai.codex"))
            #expect(store.contains("COM.MICROSOFT.VSCODE"))
            #expect(store.contains("com.qodercn.app"))
            #expect(store.contains("com.kingsoft.wpsoffice.mac.global"))
            #expect(!store.contains(nil))
            #expect(!store.contains("unknown.app"))
        }

        @Test func refreshReplacesListAndPersistsItAcrossLaunches() async throws {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let cache = directory.appendingPathComponent("list.json")
            let baseline = try data(1, ["old.app"])
            let remote = try data(2, ["new.app"])
            let store = AppCompatibilityStore(bundledData: baseline, cacheURL: cache, fetch: { remote })
            #expect(store.contains("old.app"))
            await store.refresh()
            #expect(store.contains("new.app"))
            #expect(store.refreshState == .updated)
            #expect(!store.contains("old.app"))
            let relaunched = AppCompatibilityStore(bundledData: baseline, cacheURL: cache)
            #expect(relaunched.revision == 2)
            #expect(relaunched.contains("new.app"))
            #expect(!relaunched.contains("old.app"))
            await store.refresh()
            #expect(store.refreshState == .upToDate)
        }

        @Test func invalidAndStaleUpdatesPreserveLastGoodCache() async throws {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let cache = directory.appendingPathComponent("list.json")
            let baseline = try data(1, ["bundled.app"])
            let good = try data(3, ["cached.app"])
            try good.write(to: cache)
            for remote in [
                Data("invalid".utf8), try data(4, ["new.app"], schema: 2),
                try data(4, ["bad identifier"]), try data(4, ["new.app", "new.app"]),
                try data(2, ["stale.app"]), try data(3, ["changed.app"]),
            ] {
                let store = AppCompatibilityStore(bundledData: baseline, cacheURL: cache, fetch: { remote })
                await store.refresh()
                #expect(store.revision == 3)
                #expect(store.contains("cached.app"))
                #expect(try Data(contentsOf: cache) == good)
            }
        }

        @Test func offlineAndCorruptCacheUseBundledDefaults() async throws {
            let cache = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: cache) }
            try Data("broken".utf8).write(to: cache)
            let store = AppCompatibilityStore(
                bundledData: try data(1, ["bundled.app"]), cacheURL: cache,
                fetch: { throw URLError(.notConnectedToInternet) })
            await store.refresh()
            #expect(store.contains("bundled.app"))
            #expect(store.revision == 1)
            #expect(store.refreshState == .failed)
            #expect(!store.isRefreshing)
        }

        @Test func checkingStatePreventsDuplicateRequestsAndAllowsRetryAfterFailure() async throws {
            var pending: CheckedContinuation<Data, any Error>?
            var requests = 0
            let store = AppCompatibilityStore(bundledData: try data(1, ["bundled.app"])) {
                requests += 1
                return try await withCheckedThrowingContinuation { pending = $0 }
            }
            let first = Task { await store.refresh() }
            while pending == nil { await Task.yield() }
            #expect(store.refreshState == .checking)
            #expect(store.isRefreshing)
            await store.refresh()
            #expect(requests == 1)
            pending?.resume(throwing: URLError(.notConnectedToInternet))
            await first.value
            #expect(store.refreshState == .failed)

            pending = nil
            let retry = Task { await store.refresh() }
            while pending == nil { await Task.yield() }
            pending?.resume(returning: try data(2, ["new.app"]))
            await retry.value
            #expect(requests == 2)
            #expect(store.refreshState == .updated)
            #expect(!store.isRefreshing)
            #expect(store.contains("new.app"))
        }

        @Test func newerBundledConfigurationSupersedesOldCache() throws {
            let cache = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: cache) }
            try data(2, ["cached.app"]).write(to: cache)
            let store = AppCompatibilityStore(bundledData: try data(3, ["bundled.app"]), cacheURL: cache)
            #expect(store.contains("bundled.app"))
            #expect(!store.contains("cached.app"))
        }

        @Test func higherRevisionCanRevokeAllCompatibilityEntries() async throws {
            let remote = try data(2, [])
            let store = AppCompatibilityStore(bundledData: try data(1, ["old.app"]), fetch: { remote })
            await store.refresh()
            #expect(store.revision == 2)
            #expect(!store.contains("old.app"))
        }
    }
#endif
