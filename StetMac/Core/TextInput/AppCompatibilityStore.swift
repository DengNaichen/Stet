#if os(macOS)
    import Foundation
    import Combine
    import os

    /// Supplies an in-memory compatibility list; refresh and disk access never run during paste.
    @MainActor
    final class AppCompatibilityStore: ObservableObject {
        enum RefreshState: Equatable {
            case idle
            case checking
            case updated
            case upToDate
            case failed
        }

        @Published private(set) var refreshState: RefreshState = .idle

        var isRefreshing: Bool { refreshState == .checking }

        struct Configuration: Codable {
            let schemaVersion: Int
            let revision: Int
            let bundleIDs: [String]

            static func decode(_ data: Data) throws -> Self {
                guard data.count <= 262_144 else { throw ConfigurationError.invalid }
                let value = try JSONDecoder().decode(Self.self, from: data)
                let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-_")
                guard value.schemaVersion == 1, value.revision > 0, value.bundleIDs.count <= 1_000,
                    Set(value.bundleIDs).count == value.bundleIDs.count,
                    value.bundleIDs.allSatisfy({ identifier in
                        !identifier.isEmpty && identifier.count <= 255 && identifier.contains(".")
                            && identifier.unicodeScalars.allSatisfy { allowed.contains($0) }
                    })
                else { throw ConfigurationError.invalid }
                return value
            }
        }

        private enum ConfigurationError: Error { case invalid }
        private static let logger = Logger(subsystem: "NaichengDeng.Stet", category: "AppCompatibility")
        private static let remoteURL = URL(
            string:
                "https://raw.githubusercontent.com/DengNaichen/Stet/main/StetMac/Resources/app-compatibility.json"
        )!
        private static let refreshInterval: Duration = .seconds(86_400)

        @Published private(set) var revision: Int
        private var bundleIDs: Set<String>
        private let cacheURL: URL?
        private let fetch: () async throws -> Data
        private var refreshTask: Task<Void, Never>?

        init(
            bundledData: Data? = nil,
            cacheURL: URL? = nil,
            fetch: @escaping () async throws -> Data = AppCompatibilityStore.download
        ) {
            let bundled =
                bundledData
                ?? Bundle.main.url(forResource: "app-compatibility", withExtension: "json")
                .flatMap { try? Data(contentsOf: $0) }
            let baseline =
                bundled.flatMap { try? Configuration.decode($0) }
                ?? Configuration(schemaVersion: 1, revision: 1, bundleIDs: [])
            var current = baseline
            if let cacheURL, let data = try? Data(contentsOf: cacheURL),
                let cached = try? Configuration.decode(data), cached.revision > baseline.revision
            {
                current = cached
            }
            revision = current.revision
            bundleIDs = Set(current.bundleIDs)
            self.cacheURL = cacheURL
            self.fetch = fetch
        }

        deinit { refreshTask?.cancel() }

        static func live() -> AppCompatibilityStore {
            let cacheURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first?
                .appendingPathComponent(Bundle.main.bundleIdentifier ?? "NaichengDeng.Stet", isDirectory: true)
                .appendingPathComponent("app-compatibility.json")
            let store = AppCompatibilityStore(cacheURL: cacheURL)
            store.startRefreshing()
            return store
        }

        func contains(_ bundleIdentifier: String?) -> Bool {
            guard let bundleIdentifier else { return false }
            return bundleIDs.contains(bundleIdentifier.lowercased())
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
                let configuration = try Configuration.decode(data)
                guard configuration.revision > revision else {
                    refreshState = .upToDate
                    return
                }
                if let cacheURL {
                    try FileManager.default.createDirectory(
                        at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try data.write(to: cacheURL, options: .atomic)
                }
                bundleIDs = Set(configuration.bundleIDs)
                revision = configuration.revision
                refreshState = .updated
            } catch {
                refreshState = .failed
                Self.logger.debug("Compatibility refresh unavailable; retaining the current list.")
            }
        }

        private static func download() async throws -> Data {
            var request = URLRequest(url: remoteURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
                throw ConfigurationError.invalid
            }
            return data
        }
    }
#endif
