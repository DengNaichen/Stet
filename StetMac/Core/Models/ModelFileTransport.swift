import Foundation
import HuggingFace

/// Hub caching is used only for HF-compatible endpoints. ModelScope and GitHub
/// are ordinary downloads, with Foundation resume data retained across retries.
nonisolated struct ModelFileTransport: Sendable {
    static var defaultCache: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Stet/ModelDownloads", isDirectory: true)
    }
    let cache: URL

    struct HubFile: Equatable, Sendable {
        let host: URL
        let repository: String
        let revision: String
        let path: String

        init?(_ url: URL) {
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                ["huggingface.co", "hf-mirror.com"].contains(components.host), components.query == nil
            else { return nil }
            let pieces = components.percentEncodedPath.split(separator: "/")
                .map { String($0).removingPercentEncoding ?? String($0) }
            guard pieces.count >= 5, pieces[2] == "resolve",
                let host = URL(string: "https://\(components.host!)")
            else { return nil }
            self.host = host
            repository = pieces[0] + "/" + pieces[1]
            revision = pieces[3]
            path = pieces[4...].joined(separator: "/")
        }
    }

    func download(
        _ url: URL, to destination: URL, progress: @escaping ModelFileDownloader.ProgressHandler
    ) async throws {
        try await ModelDownloadLock.withLock(key: "source:\(url.absoluteString)", cache: cache) {
            try await downloadLocked(url, to: destination, progress: progress)
        }
    }

    private func downloadLocked(
        _ url: URL, to destination: URL, progress: @escaping ModelFileDownloader.ProgressHandler
    ) async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 1800
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let resume = cache.appendingPathComponent("resume/\(ModelFileDownloader.digest(url.absoluteString)).data")
        do {
            let hubFile = HubFile(url)
            let hubCache = HubCache(
                cacheDirectory: cache.appendingPathComponent("hub/\(ModelFileDownloader.digest(url.absoluteString))"))
            if let file = hubFile {
                let client = HubClient(session: session, host: file.host, bearerToken: nil, cache: hubCache)
                // Keep official snapshot/ETag indexing, but not its network transfer:
                // 1.0.0 drops native resume data when its download task is canceled.
                if (try? await client.downloadFile(
                    at: file.path, from: Repo.ID(rawValue: file.repository)!, to: destination,
                    revision: file.revision, localFilesOnly: true)) != nil
                {
                    progress(1)
                    return
                }
            }
            try Task.checkCancellation()
            var head: HTTPURLResponse?
            if hubFile != nil {
                var request = URLRequest(url: url)
                request.httpMethod = "HEAD"
                head =
                    (try? await session.data(for: request, delegate: MetadataRedirectPolicy()))?.1 as? HTTPURLResponse
            }
            try Task.checkCancellation()
            var response: HTTPURLResponse?
            if let data = try? Data(contentsOf: resume) {
                do {
                    response = try await rawDownload(
                        url, to: destination, session: session, resumeData: data, progress: progress)
                } catch {
                    if Task.isCancelled { throw error }
                    try? FileManager.default.removeItem(at: resume)
                }
            }
            if response == nil {
                response = try await rawDownload(
                    url, to: destination, session: session, resumeData: nil, progress: progress)
            }
            try Task.checkCancellation()
            if let file = hubFile {
                let etag =
                    head?.value(forHTTPHeaderField: "X-Linked-Etag") ?? head?.value(forHTTPHeaderField: "ETag")
                    ?? response?.value(forHTTPHeaderField: "ETag")
                let commit =
                    head?.value(forHTTPHeaderField: "X-Repo-Commit")
                    ?? (file.revision.count == 40 && file.revision.allSatisfy(\.isHexDigit) ? file.revision : nil)
                if let etag, let commit {
                    try? await hubCache.storeFile(
                        at: destination, repo: Repo.ID(rawValue: file.repository)!, kind: .model,
                        revision: commit, filename: file.path, etag: etag,
                        ref: file.revision == commit ? nil : file.revision)
                }
            }
            try? FileManager.default.removeItem(at: resume)
        } catch {
            if let data = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
                try? FileManager.default.createDirectory(
                    at: resume.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? data.write(to: resume, options: .atomic)
            }
            throw error
        }
    }

    private func rawDownload(
        _ url: URL, to destination: URL, session: URLSession, resumeData: Data?,
        progress: @escaping ModelFileDownloader.ProgressHandler
    ) async throws -> HTTPURLResponse {
        let delegate = FileProgress(progress: progress)
        let temporary: URL
        let response: URLResponse
        let downloadSession = URLSession(configuration: session.configuration, delegate: delegate, delegateQueue: nil)
        defer { downloadSession.invalidateAndCancel() }
        let control = ResumableDownload()
        (temporary, response) = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                control.start(session: downloadSession, url: url, resumeData: resumeData, continuation: continuation)
            }
        } onCancel: {
            control.cancel()
        }
        defer { try? FileManager.default.removeItem(at: temporary) }
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, [200, 206].contains(http.statusCode) else {
            throw ModelFileDownloadError.invalidResponse(url, (response as? HTTPURLResponse)?.statusCode)
        }
        // A fresh request must never install an unsolicited partial response.
        guard resumeData != nil || http.statusCode == 200 else {
            throw ModelFileDownloadError.invalidResponse(url, http.statusCode)
        }
        try FileManager.default.moveItem(at: temporary, to: destination)
        return http
    }
}

private nonisolated final class FileProgress: NSObject, URLSessionDownloadDelegate, Sendable {
    let progress: ModelFileDownloader.ProgressHandler
    init(progress: @escaping ModelFileDownloader.ProgressHandler) { self.progress = progress }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
    }
    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        progress(min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
    }
}

/// The lock protects cancellation/task publication and exactly-once completion.
/// Cancellation waits for Foundation's resume-data callback before releasing the
/// destination job, so an immediate retry can see the persisted resume metadata.
private nonisolated final class ResumableDownload: @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionDownloadTask?
    private var continuation: CheckedContinuation<(URL, URLResponse), any Error>?
    private var cancelled = false
    private var finished = false

    func start(
        session: URLSession, url: URL, resumeData: Data?,
        continuation: CheckedContinuation<(URL, URLResponse), any Error>
    ) {
        let completion: @Sendable (URL?, URLResponse?, (any Error)?) -> Void = { location, response, error in
            if let error { self.finish(.failure(error)); return }
            guard let location, let response else { self.finish(.failure(URLError(.badServerResponse))); return }
            let saved = FileManager.default.temporaryDirectory.appendingPathComponent("stet-model-\(UUID().uuidString)")
            do {
                try FileManager.default.moveItem(at: location, to: saved)
                self.finish(.success((saved, response)))
            } catch { self.finish(.failure(error)) }
        }
        let task =
            resumeData.map { session.downloadTask(withResumeData: $0, completionHandler: completion) }
            ?? session.downloadTask(with: url, completionHandler: completion)
        let wasCancelled = lock.withLock {
            self.continuation = continuation
            self.task = task
            return cancelled
        }
        if wasCancelled { cancel(task) } else { task.resume() }
    }

    func cancel() {
        let task = lock.withLock { () -> URLSessionDownloadTask? in
            guard !cancelled, !finished else { return nil }
            cancelled = true
            return self.task
        }
        if let task { cancel(task) }
    }

    private func cancel(_ task: URLSessionDownloadTask) {
        task.cancel { data in
            var info: [String: Any] = [:]
            if let data { info[NSURLSessionDownloadTaskResumeData] = data }
            self.finish(
                .failure(NSError(domain: NSURLErrorDomain, code: URLError.cancelled.rawValue, userInfo: info)),
                cancellation: true)
        }
    }

    private func finish(_ result: Result<(URL, URLResponse), any Error>, cancellation: Bool = false) {
        let continuation = lock.withLock { () -> CheckedContinuation<(URL, URLResponse), any Error>? in
            guard !finished, !cancelled || cancellation else { return nil }
            finished = true
            let pending = self.continuation
            self.continuation = nil
            task = nil
            return pending
        }
        if let continuation {
            continuation.resume(with: result)
        } else if case .success(let value) = result {
            try? FileManager.default.removeItem(at: value.0)
        }
    }
}

private nonisolated final class MetadataRedirectPolicy: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        // Capture Hub metadata before redirecting to a signed CDN URL.
        completionHandler(nil)
    }
}
