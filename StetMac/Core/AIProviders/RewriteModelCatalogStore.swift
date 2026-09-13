#if os(macOS)
    import Combine
    import Foundation
    import os
    import StetCore

    struct RewriteModelDescriptor: Codable, Identifiable, Sendable, Equatable, Hashable {
        let id: String
        let displayName: String
        let enabled: Bool
    }

    struct RewriteProviderCatalog: Codable, Sendable, Equatable {
        let id: String
        let enabled: Bool
        let defaultModelID: String
        let models: [RewriteModelDescriptor]
    }

    struct RewriteModelCatalog: Codable, Sendable, Equatable {
        let schemaVersion: Int
        let revision: Int
        let providers: [RewriteProviderCatalog]

        static func decode(_ data: Data) throws -> Self {
            guard data.count <= 262_144 else { throw RewriteModelCatalogError.invalid }
            let value = try JSONDecoder().decode(Self.self, from: data)
            let allowedProviders = Set(DictationProvider.allCases.map(\.rawValue))
                .subtracting([DictationProvider.appleIntelligence.rawValue, DictationProvider.custom.rawValue])
            let identifier = try NSRegularExpression(pattern: #"^[A-Za-z0-9][A-Za-z0-9._/-]{0,254}$"#)
            func validID(_ value: String) -> Bool {
                identifier.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil
            }
            guard value.schemaVersion == 1, value.revision > 0, value.providers.count <= 32,
                Set(value.providers.map(\.id)).count == value.providers.count
            else { throw RewriteModelCatalogError.invalid }
            for provider in value.providers {
                guard allowedProviders.contains(provider.id), provider.models.count <= 100,
                    !provider.defaultModelID.isEmpty,
                    Set(provider.models.map(\.id)).count == provider.models.count,
                    provider.models.allSatisfy({
                        validID($0.id) && !$0.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            && $0.displayName.count <= 100
                    }),
                    provider.models.contains(where: { $0.id == provider.defaultModelID && $0.enabled })
                else { throw RewriteModelCatalogError.invalid }
            }
            return value
        }

        func provider(_ provider: DictationProvider) -> RewriteProviderCatalog? {
            providers.first { $0.id == provider.rawValue }
        }

        func availableModels(for provider: DictationProvider) -> [RewriteModelDescriptor] {
            guard let descriptor = self.provider(provider), descriptor.enabled else { return [] }
            return descriptor.models.filter(\.enabled)
        }

        func resolvedModelID(for provider: DictationProvider, preferredID: String?) -> String? {
            guard let descriptor = self.provider(provider), descriptor.enabled else { return nil }
            if let preferredID, descriptor.models.contains(where: { $0.id == preferredID && $0.enabled }) {
                return preferredID
            }
            return descriptor.models.contains(where: { $0.id == descriptor.defaultModelID && $0.enabled })
                ? descriptor.defaultModelID : nil
        }
    }

    private enum RewriteModelCatalogError: Error { case invalid }

    final class RewriteModelCatalogSource: @unchecked Sendable {
        private let lock = NSLock()
        private var value: RewriteModelCatalog

        init(_ value: RewriteModelCatalog) { self.value = value }
        func snapshot() -> RewriteModelCatalog { lock.withLock { value } }
        func replace(with value: RewriteModelCatalog) { lock.withLock { self.value = value } }
    }

    @MainActor
    final class RewriteModelCatalogStore: ObservableObject {
        enum RefreshState: Equatable { case idle, checking, updated, upToDate, failed }

        static let shared = RewriteModelCatalogStore.live()
        private static let logger = Logger(subsystem: "NaichengDeng.Stet", category: "RewriteModelCatalog")
        private static let remoteURL = URL(
            string: "https://raw.githubusercontent.com/DengNaichen/Stet/main/StetMac/Resources/rewrite-models.json")!
        private static let refreshInterval: Duration = .seconds(86_400)

        @Published private(set) var refreshState: RefreshState = .idle
        @Published private(set) var catalog: RewriteModelCatalog
        let source: RewriteModelCatalogSource
        private let cacheURL: URL?
        private let fetch: () async throws -> Data
        private var refreshTask: Task<Void, Never>?
        var isRefreshing: Bool { refreshState == .checking }
        var revision: Int { catalog.revision }

        init(
            bundledData: Data? = nil,
            cacheURL: URL? = nil,
            fetch: @escaping () async throws -> Data = RewriteModelCatalogStore.download
        ) {
            let bundled =
                bundledData
                ?? Bundle.main.url(forResource: "rewrite-models", withExtension: "json")
                .flatMap { try? Data(contentsOf: $0) }
            let fallback = RewriteModelCatalog(
                schemaVersion: 1, revision: 1,
                providers: [
                    RewriteProviderCatalog(
                        id: DictationProvider.openAI.rawValue, enabled: true,
                        defaultModelID: "gpt-5.6-luna",
                        models: [RewriteModelDescriptor(id: "gpt-5.6-luna", displayName: "GPT-5.6 Luna", enabled: true)]
                    )
                ])
            let baseline = bundled.flatMap { try? RewriteModelCatalog.decode($0) } ?? fallback
            var current = baseline
            if let cacheURL, let data = try? Data(contentsOf: cacheURL),
                let cached = try? RewriteModelCatalog.decode(data), cached.revision > baseline.revision
            {
                current = cached
            }
            catalog = current
            source = RewriteModelCatalogSource(current)
            self.cacheURL = cacheURL
            self.fetch = fetch
        }

        deinit { refreshTask?.cancel() }

        static func live() -> RewriteModelCatalogStore {
            let cacheURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                .appendingPathComponent(Bundle.main.bundleIdentifier ?? "NaichengDeng.Stet", isDirectory: true)
                .appendingPathComponent("rewrite-models.json")
            let store = RewriteModelCatalogStore(cacheURL: cacheURL)
            store.startRefreshing()
            return store
        }

        func availableModels(for provider: DictationProvider) -> [RewriteModelDescriptor] {
            catalog.availableModels(for: provider)
        }

        func startRefreshing() {
            guard refreshTask == nil else { return }
            refreshTask = Task { [weak self] in
                while !Task.isCancelled {
                    await self?.refresh()
                    do { try await Task.sleep(for: Self.refreshInterval) } catch { return }
                }
            }
        }

        func refresh() async {
            guard !isRefreshing else { return }
            refreshState = .checking
            do {
                let data = try await fetch()
                try Task.checkCancellation()
                let next = try RewriteModelCatalog.decode(data)
                guard next.revision > catalog.revision else { refreshState = .upToDate; return }
                if let cacheURL {
                    try FileManager.default.createDirectory(
                        at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try data.write(to: cacheURL, options: .atomic)
                }
                catalog = next
                source.replace(with: next)
                refreshState = .updated
            } catch {
                refreshState = .failed
                Self.logger.debug("Rewrite model catalog refresh unavailable; retaining current catalog.")
            }
        }

        private static func download() async throws -> Data {
            var request = URLRequest(url: remoteURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
                throw RewriteModelCatalogError.invalid
            }
            return data
        }
    }
#endif
