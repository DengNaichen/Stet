#if os(macOS)
    import CoreML
    import FluidAudio
    import Foundation
    import StetCore

    /// Owns the meeting model cache. Loading never starts a download or deletes a cache.
    nonisolated struct MeetingSpeakerModelStore: Sendable {
        struct File: Sendable {
            let path: String
            let size: Int64
        }

        static let revision = "ae9a27ab45dc0aa3abede7d2d6bad2b7a69aa6d1"
        static let bundle = "v3/fp16/SortformerEfficient_v2.1.mlmodelc"
        static let manifest: [File] = [
            .init(path: "analytics/coremldata.bin", size: 202),
            .init(path: "coremldata.bin", size: 1094),
            .init(path: "model0/analytics/coremldata.bin", size: 108),
            .init(path: "model0/coremldata.bin", size: 633),
            .init(path: "model0/model.mil", size: 33213),
            .init(path: "model0/weights/0-weight.bin", size: 8948544),
            .init(path: "model1/analytics/coremldata.bin", size: 108),
            .init(path: "model1/coremldata.bin", size: 593),
            .init(path: "model1/model.mil", size: 1205553),
            .init(path: "model1/weights/1-weight.bin", size: 231089728),
        ]
        static var defaultDirectory: URL {
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("FluidAudio/Models/sortformer/\(bundle)")
        }

        let directory: URL
        private let files: [File]
        private let download: @Sendable (File, URL, @escaping @Sendable (Double) -> Void) async throws -> Void
        private let validate: @Sendable (URL) async throws -> Void

        init(
            directory: URL = Self.defaultDirectory,
            files: [File] = Self.manifest,
            download: @escaping @Sendable (File, URL, @escaping @Sendable (Double) -> Void) async throws -> Void = Self
                .downloadFile,
            validate: @escaping @Sendable (URL) async throws -> Void = Self.validateModel
        ) {
            self.directory = directory
            self.files = files
            self.download = download
            self.validate = validate
        }

        var isComplete: Bool { files.allSatisfy { isComplete($0) } }

        func checkReady() async throws {
            guard isComplete else { throw ModelError.incomplete }
            try await validate(directory)
        }

        func prepare(progress: @escaping @Sendable (Double) -> Void) async throws {
            let total = Double(files.reduce(Int64(0)) { $0 + $1.size })
            var completed: Int64 = 0
            for file in files {
                try Task.checkCancellation()
                if !isComplete(file) {
                    let destination = directory.appendingPathComponent(file.path)
                    try FileManager.default.createDirectory(
                        at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                    let base = Double(completed)
                    try await download(file, destination) { fraction in
                        progress((base + fraction * Double(file.size)) / total)
                    }
                    guard isComplete(file) else { throw ModelError.incomplete }
                }
                completed += file.size
                progress(Double(completed) / total)
            }
            try Task.checkCancellation()
            try await checkReady()
        }

        private func isComplete(_ file: File) -> Bool {
            let values = try? directory.appendingPathComponent(file.path).resourceValues(forKeys: [
                .fileSizeKey, .isRegularFileKey,
            ])
            return values?.isRegularFile == true && values?.fileSize.map(Int64.init) == file.size
        }

        static func loadLocalModel(at directory: URL) throws -> MLModel {
            let configuration = MLModelConfiguration()
            configuration.computeUnits = SortformerModels.recommendedComputeUnits(for: .efficientV2_1)
            return try MLModel(contentsOf: directory, configuration: configuration)
        }

        private static func validateModel(at directory: URL) async throws {
            try await Task.detached(priority: .utility) {
                _ = try loadLocalModel(at: directory)
            }.value
            try Task.checkCancellation()
        }

        private static func downloadFile(
            _ file: File, to destination: URL, progress: @escaping @Sendable (Double) -> Void
        ) async throws {
            let official = URL(
                string:
                    "https://huggingface.co/FluidInference/diar-streaming-sortformer-coreml/resolve/\(revision)/\(bundle)/\(file.path)"
            )!
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 60
            configuration.timeoutIntervalForResource = 1800
            let session = URLSession(configuration: configuration)
            defer { session.invalidateAndCancel() }
            var lastError: any Error = ModelError.incomplete
            for url in ModelDownloadMirror.candidates(for: official) {
                do {
                    try Task.checkCancellation()
                    let delegate = ModelDownloadProgress(size: file.size, progress: progress)
                    let (temporary, response) = try await session.download(
                        for: URLRequest(url: url), delegate: delegate)
                    defer { try? FileManager.default.removeItem(at: temporary) }
                    try Task.checkCancellation()
                    guard let response = response as? HTTPURLResponse, response.statusCode == 200,
                        (try temporary.resourceValues(forKeys: [.fileSizeKey])).fileSize.map(Int64.init) == file.size
                    else { throw ModelError.invalidDownload }
                    // Only replace this incomplete file; completed siblings survive errors and cancellation.
                    if FileManager.default.fileExists(atPath: destination.path) {
                        try FileManager.default.removeItem(at: destination)
                    }
                    try FileManager.default.moveItem(at: temporary, to: destination)
                    return
                } catch {
                    try Task.checkCancellation()
                    lastError = error
                }
            }
            throw lastError
        }

        enum ModelError: LocalizedError {
            case incomplete, invalidDownload
            var errorDescription: String? {
                switch self {
                case .incomplete:
                    String(
                        localized:
                            "The speaker separation model is incomplete. Download it before enabling speaker separation."
                    )
                case .invalidDownload:
                    String(
                        localized: "The model download was incomplete or invalid. Retry to download the missing files.")
                }
            }
        }
    }

    private nonisolated final class ModelDownloadProgress: NSObject, URLSessionDownloadDelegate, Sendable {
        let size: Int64
        let progress: @Sendable (Double) -> Void
        init(size: Int64, progress: @escaping @Sendable (Double) -> Void) {
            self.size = size
            self.progress = progress
        }
        func urlSession(
            _ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL
        ) {}
        func urlSession(
            _ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
            totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
        ) {
            progress(min(1, Double(totalBytesWritten) / Double(size)))
        }
    }
#endif
