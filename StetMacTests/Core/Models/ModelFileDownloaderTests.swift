import Foundation
import Testing
@testable import Stet

struct ModelFileDownloaderTests {
    private let first = URL(string: "https://example.com/first")!
    private let second = URL(string: "https://example.com/second")!
    private let abcHash = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"

    @Test func localOnlyReusesLegacyFileAndNeverStartsNetworkOrCreatesCache() async throws {
        let root = TestSupport.temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let cache = root.appendingPathComponent("cache")
        let destination = root.appendingPathComponent("model")
        try Data("abc".utf8).write(to: destination)
        let downloader = ModelFileDownloader(cache: cache) { _, _, _ in Issue.record("Unexpected download") }
        let request = ModelFileRequest(sources: [first], size: 3, sha256: abcHash)
        #expect(try await downloader.file(request, at: destination, localFilesOnly: true) == destination)
        await #expect(throws: ModelFileDownloadError.self) {
            try await downloader.file(request, at: root.appendingPathComponent("missing"), localFilesOnly: true)
        }
        #expect(!FileManager.default.fileExists(atPath: cache.path))
    }

    @Test func invalidMirrorCannotReplaceExistingFileAndNextMirrorCanRecover() async throws {
        let root = TestSupport.temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let destination = root.appendingPathComponent("model")
        try Data("old".utf8).write(to: destination)
        let calls = DownloadCalls()
        let downloader = ModelFileDownloader(cache: root.appendingPathComponent("cache")) { url, temporary, _ in
            await calls.append(url)
            #expect(try Data(contentsOf: destination) == Data("old".utf8))
            try Data((url.lastPathComponent == "first" ? "bad" : "abc").utf8).write(to: temporary)
        }
        let request = ModelFileRequest(sources: [first, second], size: 3, sha256: abcHash)
        _ = try await downloader.file(request, at: destination)
        #expect(await calls.urls == [first, second])
        #expect(try Data(contentsOf: destination) == Data("abc".utf8))
        #expect(
            try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0.hasPrefix(".download-") }.isEmpty
        )
    }

    @Test func corruptHubCacheRetriesSameSourceWithoutReplacingExistingFileEarly() async throws {
        let root = TestSupport.temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = root.appendingPathComponent("cache")
        let hub = cache.appendingPathComponent("hub/\(ModelFileDownloader.digest(first.absoluteString))")
        try FileManager.default.createDirectory(at: hub, withIntermediateDirectories: true)
        let destination = root.appendingPathComponent("model")
        try Data("old".utf8).write(to: destination)
        let calls = DownloadCalls()
        let downloader = ModelFileDownloader(cache: cache) { url, staging, _ in
            let count = await calls.append(url)
            #expect(try Data(contentsOf: destination) == Data("old".utf8))
            try Data((count == 1 ? "b" : "abc").utf8).write(to: staging)
        }
        _ = try await downloader.file(ModelFileRequest(sources: [first], size: 3, sha256: abcHash), at: destination)
        #expect(await calls.urls.count == 2)
        #expect(try Data(contentsOf: destination) == Data("abc".utf8))
    }

    @Test func receiptDetectsTruncationWithoutChangingLegacyFileLocations() async throws {
        let root = TestSupport.temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appendingPathComponent("model")
        let calls = DownloadCalls()
        let downloader = ModelFileDownloader(cache: root.appendingPathComponent("cache")) { url, temporary, _ in
            await calls.append(url)
            try Data("abc".utf8).write(to: temporary)
        }
        let request = ModelFileRequest(sources: [first])
        _ = try await downloader.file(request, at: destination)
        try Data("a".utf8).write(to: destination)
        #expect(!downloader.isAvailable(request, at: destination))
        _ = try await downloader.file(request, at: destination)
        #expect(await calls.urls.count == 2)
        #expect(try Data(contentsOf: destination) == Data("abc".utf8))
    }

    @Test func cancelingOneSubscriberDoesNotCancelAnotherSubscriber() async throws {
        let root = TestSupport.temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: root) }
        let gate = DownloadGate()
        let downloader = ModelFileDownloader(cache: root.appendingPathComponent("cache")) { _, temporary, _ in
            await gate.started()
            await gate.wait()
            try Data("abc".utf8).write(to: temporary)
        }
        let request = ModelFileRequest(sources: [first], size: 3)
        let destination = root.appendingPathComponent("model")
        let progress: ModelFileDownloader.ProgressHandler = { value in
            if value == 0 { Task { await gate.joined() } }
        }
        let a = Task { try await downloader.file(request, at: destination, progress: progress) }
        let b = Task { try await downloader.file(request, at: destination, progress: progress) }
        try #require(await TestSupport.eventuallyAsync { await gate.subscribers == 2 })
        a.cancel()
        await #expect(throws: CancellationError.self) { try await a.value }
        await gate.open()
        #expect(try await b.value == destination)
        #expect(await gate.starts == 1)
    }

    @Test func cancelingLastSubscriberStopsTransferAndAllowsRetry() async throws {
        let root = TestSupport.temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: root) }
        let calls = DownloadCalls()
        let downloader = ModelFileDownloader(cache: root.appendingPathComponent("cache")) { url, temporary, _ in
            let count = await calls.append(url)
            if count == 1 { try await Task.sleep(for: .seconds(30)) }
            try Data("abc".utf8).write(to: temporary)
        }
        let request = ModelFileRequest(sources: [first], size: 3)
        let destination = root.appendingPathComponent("model")
        let task = Task { try await downloader.file(request, at: destination) }
        try #require(await TestSupport.eventuallyAsync { await calls.urls.count == 1 })
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try await downloader.file(request, at: destination) == destination)
        #expect(await calls.urls.count == 2)
    }

    @Test func separateDownloadersShareDestinationLock() async throws {
        let root = TestSupport.temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: root) }
        let calls = DownloadCalls()
        let transfer: ModelFileDownloader.Transfer = { url, temporary, _ in
            await calls.append(url)
            try await Task.sleep(for: .milliseconds(100))
            try Data("abc".utf8).write(to: temporary)
        }
        let a = ModelFileDownloader(cache: root.appendingPathComponent("cache"), transfer: transfer)
        let b = ModelFileDownloader(cache: root.appendingPathComponent("cache"), transfer: transfer)
        let request = ModelFileRequest(sources: [first], size: 3)
        let destination = root.appendingPathComponent("model")
        async let x = a.file(request, at: destination)
        async let y = b.file(request, at: destination)
        _ = try await (x, y)
        #expect(await calls.urls.count == 1)
    }

    @Test func fixedRevisionNeverFallsBackToModelScopeMaster() {
        let commit = String(repeating: "a", count: 40)
        let url = URL(string: "https://huggingface.co/FunAudioLLM/Fun-ASR-Nano-GGUF/resolve/\(commit)/encoder.gguf")!
        let request = ModelFileRequest(official: url)
        #expect(!request.sources.contains { $0.host == "www.modelscope.cn" })
        #expect(request.sources.allSatisfy { $0.path.contains(commit) })
        let parsed = ModelFileTransport.HubFile(url)
        #expect(parsed?.repository == "FunAudioLLM/Fun-ASR-Nano-GGUF")
        #expect(parsed?.revision == commit)
        #expect(
            ModelFileTransport.HubFile(URL(string: "https://www.modelscope.cn/models/x/y/resolve/master/model")!) == nil
        )
    }
}

private actor DownloadCalls {
    var urls: [URL] = []
    @discardableResult func append(_ url: URL) -> Int { urls.append(url); return urls.count }
}
private actor DownloadGate {
    var starts = 0
    var subscribers = 0
    var waiters: [CheckedContinuation<Void, Never>] = []
    private var isOpen = false
    func started() { starts += 1 }
    func joined() { subscribers += 1 }
    func wait() async { if !isOpen { await withCheckedContinuation { waiters.append($0) } } }
    func open() { isOpen = true; let pending = waiters; waiters.removeAll(); pending.forEach { $0.resume() } }
}
