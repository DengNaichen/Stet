import CryptoKit
import Darwin
import Foundation
import StetCore

/// A file contract; model parsing and directory ownership stay with the caller.
nonisolated struct ModelFileRequest: Hashable, Sendable {
    let sources: [URL]
    let size: Int64?
    let sha256: String?

    init(sources: [URL], size: Int64? = nil, sha256: String? = nil) {
        self.sources = sources
        self.size = size
        self.sha256 = sha256?.lowercased()
    }

    init(official: URL, github: URL? = nil, size: Int64? = nil, sha256: String? = nil) {
        let urls =
            github.map { ModelDownloadMirror.candidates(huggingFace: official, github: $0) }
            ?? ModelDownloadMirror.candidates(for: official)
        // ModelScope's master alias is not an immutable HF commit mapping.
        let revision = official.pathComponents.dropFirst(4).first
        let pinned = revision.map { $0.count == 40 && $0.allSatisfy(\.isHexDigit) } ?? false
        self.init(
            sources: urls.filter { !pinned || $0.host != ModelDownloadMirror.modelScopeOrigin },
            size: size, sha256: sha256)
    }
}

nonisolated enum ModelFileDownloadError: Error, LocalizedError {
    case missingLocalFile(URL)
    case invalidFile(URL)
    case invalidResponse(URL, Int?)
    case conflictingRequest(URL)
    case noSources

    var errorDescription: String? {
        switch self {
        case .missingLocalFile(let url): "Model file is unavailable locally: \(url.lastPathComponent)."
        case .invalidFile(let url): "Model file failed size or checksum validation: \(url.lastPathComponent)."
        case .invalidResponse(_, let status): "Model download returned an invalid response (\(status ?? 0))."
        case .conflictingRequest(let url): "A different model is already being installed at \(url.lastPathComponent)."
        case .noSources: "No model download source is configured."
        }
    }
}

/// One app-wide boundary for file reuse, transfers, coalescing and atomic installation.
actor ModelFileDownloader {
    typealias ProgressHandler = @Sendable (Double) -> Void
    typealias Transfer = @Sendable (URL, URL, @escaping ProgressHandler) async throws -> Void
    static let shared = ModelFileDownloader()

    private nonisolated struct Waiter {
        let continuation: CheckedContinuation<URL, any Error>
        let progress: ProgressHandler
    }
    private struct Job {
        let id: UUID
        let request: ModelFileRequest
        let task: Task<Void, Never>
        var waiters: [UUID: Waiter]
    }
    private var jobs: [URL: Job] = [:]
    private let transfer: Transfer
    private nonisolated let cache: URL

    init(cache: URL = ModelFileTransport.defaultCache, transfer: Transfer? = nil) {
        self.cache = cache
        let transport = ModelFileTransport(cache: cache)
        self.transfer =
            transfer ?? { url, destination, progress in
                try await transport.download(url, to: destination, progress: progress)
            }
    }

    nonisolated func isAvailable(_ request: ModelFileRequest, at destination: URL) -> Bool {
        Self.isValid(destination.standardizedFileURL, request: request, cache: cache)
    }

    func file(
        _ request: ModelFileRequest, at destination: URL, localFilesOnly: Bool = false,
        progress: @escaping ProgressHandler = { _ in }
    ) async throws -> URL {
        try Task.checkCancellation()
        let destination = destination.standardizedFileURL
        if localFilesOnly {
            guard Self.isValid(destination, request: request, cache: cache) else {
                throw ModelFileDownloadError.missingLocalFile(destination)
            }
            progress(1)
            return destination
        }
        // A canceled last subscriber stops the transfer. A new subscriber waits for
        // its cleanup before starting another job at the same destination.
        if let job = jobs[destination], job.waiters.isEmpty {
            await job.task.value
            return try await file(request, at: destination, progress: progress)
        }
        if let job = jobs[destination], job.request != request {
            throw ModelFileDownloadError.conflictingRequest(destination)
        }
        let waiterID = UUID()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                let waiter = Waiter(continuation: continuation, progress: progress)
                progress(0)
                if jobs[destination] != nil {
                    jobs[destination]?.waiters[waiterID] = waiter
                    return
                }
                let jobID = UUID()
                let transfer = self.transfer
                let cache = self.cache
                let task = Task.detached(priority: .utility) {
                    let result: Result<URL, any Error>
                    do {
                        let url = try await Self.install(request, at: destination, cache: cache, transfer: transfer) {
                            value in
                            Task { await self.broadcast(value, at: destination, jobID: jobID) }
                        }
                        result = .success(url)
                    } catch {
                        result = .failure(error)
                    }
                    await self.finish(result, at: destination, jobID: jobID)
                }
                jobs[destination] = Job(id: jobID, request: request, task: task, waiters: [waiterID: waiter])
            }
        } onCancel: {
            Task { await self.cancel(waiterID, at: destination) }
        }
    }

    private func cancel(_ waiterID: UUID, at destination: URL) {
        guard let waiter = jobs[destination]?.waiters.removeValue(forKey: waiterID) else { return }
        waiter.continuation.resume(throwing: CancellationError())
        if jobs[destination]?.waiters.isEmpty == true { jobs[destination]?.task.cancel() }
    }

    private func broadcast(_ value: Double, at destination: URL, jobID: UUID) {
        guard let job = jobs[destination], job.id == jobID else { return }
        for waiter in job.waiters.values { waiter.progress(max(0, min(1, value))) }
    }

    private func finish(_ result: Result<URL, any Error>, at destination: URL, jobID: UUID) {
        guard let job = jobs[destination], job.id == jobID else { return }
        jobs[destination] = nil
        for waiter in job.waiters.values {
            if case .success = result { waiter.progress(1) }
            waiter.continuation.resume(with: result)
        }
    }

    private nonisolated struct Receipt: Codable {
        let source: URL?
        let size: Int64
    }

    nonisolated static func digest(_ string: String) -> String {
        SHA256.hash(data: Data(string.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private nonisolated static func receiptURL(_ destination: URL, cache: URL) -> URL {
        cache.appendingPathComponent("receipts/\(digest(destination.path)).json")
    }

    nonisolated static func isValid(_ url: URL, request: ModelFileRequest, cache: URL) -> Bool {
        // URL resource values may remain cached after replacing a staging file.
        let current = URL(fileURLWithPath: url.path)
        guard let values = try? current.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
            values.isRegularFile == true, let size = values.fileSize, size > 0
        else { return false }
        if let expected = request.size, Int64(size) != expected { return false }
        if let data = try? Data(contentsOf: receiptURL(url, cache: cache)),
            let receipt = try? JSONDecoder().decode(Receipt.self, from: data),
            receipt.size != Int64(size)
                || receipt.source
                    != (request.sources.first(where: { $0.host == "huggingface.co" }) ?? request.sources.first)
        {
            return false
        }
        if let expected = request.sha256 {
            guard let actual = try? hashFile(url), actual == expected else { return false }
        }
        return true
    }

    private nonisolated static func hashFile(_ url: URL) throws -> String {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var hash = SHA256()
        while let data = try file.read(upToCount: 1_048_576), !data.isEmpty { hash.update(data: data) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private nonisolated static func install(
        _ request: ModelFileRequest, at destination: URL, cache: URL, transfer: Transfer,
        progress: @escaping ProgressHandler
    ) async throws -> URL {
        try await ModelDownloadLock.withLock(key: "destination:\(destination.path)", cache: cache) {
            try await installLocked(request, at: destination, cache: cache, transfer: transfer, progress: progress)
        }
    }

    private nonisolated static func installLocked(
        _ request: ModelFileRequest, at destination: URL, cache: URL, transfer: Transfer,
        progress: @escaping ProgressHandler
    ) async throws -> URL {
        let manager = FileManager.default
        if isValid(destination, request: request, cache: cache) { return destination }
        guard !request.sources.isEmpty else { throw ModelFileDownloadError.noSources }
        try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        var lastError: any Error = ModelFileDownloadError.noSources
        for source in request.sources {
            let staging = destination.deletingLastPathComponent().appendingPathComponent(
                ".download-\(UUID().uuidString)")
            defer { try? manager.removeItem(at: staging) }
            do {
                try Task.checkCancellation()
                let hubDirectory = cache.appendingPathComponent("hub/\(digest(source.absoluteString))")
                let hadHubCache = manager.fileExists(atPath: hubDirectory.path)
                try await transfer(source, staging, progress)
                try Task.checkCancellation()
                if !isValid(staging, request: request, cache: cache), hadHubCache {
                    // Retry once after evicting a corrupt SDK cache entry, before
                    // falling back to another source. Completed models are untouched.
                    try? manager.removeItem(at: hubDirectory)
                    try? manager.removeItem(at: staging)
                    try await transfer(source, staging, progress)
                    try Task.checkCancellation()
                }
                guard isValid(staging, request: request, cache: cache) else {
                    try? manager.removeItem(at: hubDirectory)
                    throw ModelFileDownloadError.invalidFile(destination)
                }
                let size = try staging.resourceValues(forKeys: [.fileSizeKey]).fileSize!
                guard rename(staging.path, destination.path) == 0 else {
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
                let receipt = receiptURL(destination, cache: cache)
                try manager.createDirectory(at: receipt.deletingLastPathComponent(), withIntermediateDirectories: true)
                // The validated model remains usable even if metadata cannot be cached.
                try? JSONEncoder().encode(
                    Receipt(
                        source: request.sources.first(where: { $0.host == "huggingface.co" }) ?? request.sources.first,
                        size: Int64(size))
                ).write(to: receipt, options: .atomic)
                return destination
            } catch {
                try Task.checkCancellation()
                if error is CancellationError { throw error }
                lastError = error
            }
        }
        throw lastError
    }
}

nonisolated enum ModelDownloadLock {
    static func withLock<T: Sendable>(
        key: String, cache: URL, operation: @Sendable () async throws -> T
    ) async throws -> T {
        let directory = cache.appendingPathComponent("locks", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let descriptor = open(
            directory.appendingPathComponent(ModelFileDownloader.digest(key)).path, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { flock(descriptor, LOCK_UN); close(descriptor) }
        while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            guard errno == EWOULDBLOCK else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            try await Task.sleep(for: .milliseconds(100))
        }
        try Task.checkCancellation()
        return try await operation()
    }
}
