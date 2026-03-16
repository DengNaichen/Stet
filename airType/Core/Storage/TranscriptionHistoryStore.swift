import Foundation

protocol TranscriptionHistoryStore: Sendable {
    func loadHistory() async -> [TranscriptionRecord]
    func saveHistory(_ records: [TranscriptionRecord]) async
}

actor FileTranscriptionHistoryStore: TranscriptionHistoryStore {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func loadHistory() async -> [TranscriptionRecord] {
        guard let data = try? Data(contentsOf: fileURL) else {
            return []
        }

        return (try? decoder.decode([TranscriptionRecord].self, from: data)) ?? []
    }

    func saveHistory(_ records: [TranscriptionRecord]) async {
        guard let data = try? encoder.encode(records) else {
            return
        }

        let directoryURL = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: [.atomic])
    }

    nonisolated static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        if let applicationSupport = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) {
            let directoryURL = applicationSupport.appendingPathComponent("airType", isDirectory: true)
            return directoryURL.appendingPathComponent("transcription-history.json")
        }

        return fileManager.temporaryDirectory.appendingPathComponent("airType-transcription-history.json")
    }
}
