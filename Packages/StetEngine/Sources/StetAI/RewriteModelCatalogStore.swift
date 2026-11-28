import Combine
import Foundation
import os
import StetCore

public struct RewriteModelDescriptor: Codable, Identifiable, Sendable, Equatable, Hashable {
    public let id: String
    public let displayName: String
    public let enabled: Bool
    public let thinkingLevels: [RewriteThinkingLevel]?
    public let defaultThinkingLevel: RewriteThinkingLevel?

    public init(
        id: String,
        displayName: String,
        enabled: Bool,
        thinkingLevels: [RewriteThinkingLevel]? = nil,
        defaultThinkingLevel: RewriteThinkingLevel? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.enabled = enabled
        self.thinkingLevels = thinkingLevels
        self.defaultThinkingLevel = defaultThinkingLevel
    }
}

public struct RewriteProviderCatalog: Codable, Sendable, Equatable {
    public let id: String
    public let enabled: Bool
    public let defaultModelID: String
    public let models: [RewriteModelDescriptor]

    public init(id: String, enabled: Bool, defaultModelID: String, models: [RewriteModelDescriptor]) {
        self.id = id
        self.enabled = enabled
        self.defaultModelID = defaultModelID
        self.models = models
    }
}

public struct RewriteModelCatalog: Codable, Sendable, Equatable {
    public let schemaVersion: Int
    public let revision: Int
    public let providers: [RewriteProviderCatalog]

    public init(schemaVersion: Int, revision: Int, providers: [RewriteProviderCatalog]) {
        self.schemaVersion = schemaVersion
        self.revision = revision
        self.providers = providers
    }

    public static let bundled: Self = {
        guard let url = Bundle.module.url(forResource: "rewrite-models", withExtension: "json"),
            let data = try? Data(contentsOf: url), let catalog = try? decode(data)
        else {
            // Keep local dictation available until the first valid cached or downloaded catalog.
            return Self(schemaVersion: 1, revision: 0, providers: [])
        }
        return catalog
    }()

    public static func decode(_ data: Data) throws -> Self {
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
                provider.models.allSatisfy({ model in
                    let levels = model.thinkingLevels ?? []
                    return validID(model.id)
                        && !model.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        && model.displayName.count <= 100
                        && (model.thinkingLevels == nil || !levels.isEmpty)
                        && Set(levels).count == levels.count
                        && levels.count <= RewriteThinkingLevel.allCases.count
                        && ((levels.isEmpty && model.defaultThinkingLevel == nil)
                            || model.defaultThinkingLevel.map(levels.contains) == true)
                }),
                provider.models.contains(where: { $0.id == provider.defaultModelID && $0.enabled })
            else { throw RewriteModelCatalogError.invalid }
        }
        return value
    }

    public func provider(_ provider: DictationProvider) -> RewriteProviderCatalog? {
        providers.first { $0.id == provider.rawValue }
    }

    public func availableModels(for provider: DictationProvider) -> [RewriteModelDescriptor] {
        guard let descriptor = self.provider(provider), descriptor.enabled else { return [] }
        return descriptor.models.filter(\.enabled)
    }

    public func model(for provider: DictationProvider, modelID: String) -> RewriteModelDescriptor? {
        availableModels(for: provider).first { $0.id == modelID }
    }

    public func availableThinkingLevels(for provider: DictationProvider, modelID: String?) -> [RewriteThinkingLevel] {
        guard let id = resolvedModelID(for: provider, preferredID: modelID) else { return [] }
        return model(for: provider, modelID: id)?.thinkingLevels ?? []
    }

    public func resolvedThinkingLevel(
        for provider: DictationProvider, modelID: String?, preferredLevel: RewriteThinkingLevel?
    ) -> RewriteThinkingLevel? {
        guard let id = resolvedModelID(for: provider, preferredID: modelID),
            let descriptor = model(for: provider, modelID: id)
        else { return nil }
        if let preferredLevel, descriptor.thinkingLevels?.contains(preferredLevel) == true { return preferredLevel }
        return descriptor.defaultThinkingLevel
    }

    public func isProviderEnabled(_ provider: DictationProvider) -> Bool {
        !availableModels(for: provider).isEmpty
    }

    public func resolvedModelID(for provider: DictationProvider, preferredID: String?) -> String? {
        guard let descriptor = self.provider(provider), descriptor.enabled else { return nil }
        if let preferredID, descriptor.models.contains(where: { $0.id == preferredID && $0.enabled }) {
            return preferredID
        }
        return descriptor.models.contains(where: { $0.id == descriptor.defaultModelID && $0.enabled })
            ? descriptor.defaultModelID : nil
    }
}

private enum RewriteModelCatalogError: Error { case invalid }

public final class RewriteModelCatalogSource: @unchecked Sendable {
    private let lock = NSLock()
    private var value: RewriteModelCatalog

    public init(_ value: RewriteModelCatalog) { self.value = value }
    public func snapshot() -> RewriteModelCatalog { lock.withLock { value } }
    fileprivate func replace(with value: RewriteModelCatalog) { lock.withLock { self.value = value } }
}

@MainActor
public final class RewriteModelCatalogStore: ObservableObject {
    public enum RefreshState: Equatable { case idle, checking, updated, upToDate, failed }

    public static let shared = RewriteModelCatalogStore.live()
    private static let logger = Logger(subsystem: "NaichengDeng.Stet", category: "RewriteModelCatalog")
    private static let remoteURL = URL(
        string:
            "https://raw.githubusercontent.com/DengNaichen/Stet/main/Packages/StetEngine/Sources/StetAI/Resources/rewrite-models.json"
    )!
    private static let refreshInterval: Duration = .seconds(86_400)

    @Published public private(set) var refreshState: RefreshState = .idle
    @Published public private(set) var catalog: RewriteModelCatalog
    public let source: RewriteModelCatalogSource
    private let cacheURL: URL?
    private let fetch: () async throws -> Data
    private var refreshTask: Task<Void, Never>?
    public var isRefreshing: Bool { refreshState == .checking }
    public var revision: Int { catalog.revision }

    public init(
        bundledData: Data? = nil,
        cacheURL: URL? = nil,
        fetch: (() async throws -> Data)? = nil
    ) {
        let baseline = bundledData.flatMap { try? RewriteModelCatalog.decode($0) } ?? .bundled
        var current = baseline
        if let cacheURL, let data = try? Data(contentsOf: cacheURL),
            let cached = try? RewriteModelCatalog.decode(data), cached.revision > baseline.revision
        {
            current = cached
        }
        catalog = current
        source = RewriteModelCatalogSource(current)
        self.cacheURL = cacheURL
        self.fetch = fetch ?? Self.download
    }

    deinit { refreshTask?.cancel() }

    public static func live() -> RewriteModelCatalogStore {
        let cacheURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "NaichengDeng.Stet", isDirectory: true)
            .appendingPathComponent("rewrite-models.json")
        let store = RewriteModelCatalogStore(cacheURL: cacheURL)
        store.startRefreshing()
        return store
    }

    public func availableModels(for provider: DictationProvider) -> [RewriteModelDescriptor] {
        catalog.availableModels(for: provider)
    }

    public func startRefreshing() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                do { try await Task.sleep(for: Self.refreshInterval) } catch { return }
            }
        }
    }

    public func refresh() async {
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
            source.replace(with: next)
            catalog = next
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
