#if os(macOS)
    import Foundation

    struct MeetingRecordingStore: Sendable {
        let rootDirectory: URL
        private let fileManager: FileManager

        init(
            fileManager: FileManager = .default,
            rootDirectory: URL? = nil
        ) {
            self.fileManager = fileManager
            self.rootDirectory =
                rootDirectory
                ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("Stet", isDirectory: true)
                .appendingPathComponent("Meetings", isDirectory: true)
        }

        func ensureRootDirectory() throws -> URL {
            try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
            return rootDirectory
        }

        func makeSessionDirectory(startedAt: Date) throws -> MeetingSessionDirectory {
            try ensureRootDirectory()
            let folderName = Self.folderName(for: startedAt)
            let url = rootDirectory.appendingPathComponent(folderName, isDirectory: true)
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            return MeetingSessionDirectory(url: url, startedAt: startedAt)
        }

        func sessionDirectories() throws -> [URL] {
            guard fileManager.fileExists(atPath: rootDirectory.path) else { return [] }
            let urls = try fileManager.contentsOfDirectory(
                at: rootDirectory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
            return urls.filter(\.hasDirectoryPath)
                .sorted { lhs, rhs in
                    let left =
                        (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                        ?? .distantPast
                    let right =
                        (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                        ?? .distantPast
                    return left > right
                }
        }

        func recentSessionDirectories(limit: Int = 20) throws -> [URL] {
            Array(try sessionDirectories().prefix(limit))
        }

        func sessionDirectory(id: String) -> MeetingSessionDirectory? {
            let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.contains("/"), !trimmed.contains("\\") else {
                return nil
            }
            let url = rootDirectory.appendingPathComponent(trimmed, isDirectory: true)
            var isDirectory = ObjCBool(false)
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
                isDirectory.boolValue
            else {
                return nil
            }
            return MeetingSessionDirectory(
                url: url,
                startedAt: Self.startedAt(fromFolderName: trimmed) ?? .distantPast
            )
        }

        func record(for directory: MeetingSessionDirectory) throws -> MeetingSessionRecord? {
            guard fileManager.fileExists(atPath: directory.sessionURL.path) else { return nil }
            return try MeetingSessionRecord.fromJSON(Data(contentsOf: directory.sessionURL))
        }

        func transcriptText(for directory: MeetingSessionDirectory) throws -> String? {
            guard fileManager.fileExists(atPath: directory.transcriptURL.path) else { return nil }
            return try String(contentsOf: directory.transcriptURL, encoding: .utf8)
        }

        nonisolated static func folderName(for startedAt: Date) -> String {
            folderNameFormatter().string(from: startedAt)
        }

        nonisolated static func startedAt(fromFolderName name: String) -> Date? {
            folderNameFormatter().date(from: name)
        }

        private nonisolated static func folderNameFormatter() -> DateFormatter {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
            return formatter
        }
    }

    struct MeetingSessionDirectory: Equatable, Sendable {
        let url: URL
        let startedAt: Date

        var audioURL: URL {
            url.appendingPathComponent("audio.wav")
        }

        var transcriptURL: URL {
            url.appendingPathComponent("transcript.md")
        }

        var sessionURL: URL {
            url.appendingPathComponent("session.json")
        }
    }

    struct MeetingSessionRecord: Codable, Equatable, Sendable {
        var startedAt: Date
        var endedAt: Date?
        var durationSeconds: Double
        var status: String
        var failureMessage: String?
        var speakerCount: Int
        var organizedAt: Date? = nil

        func jsonData() throws -> Data {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            return try encoder.encode(self)
        }

        static func fromJSON(_ data: Data) throws -> MeetingSessionRecord {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(Self.self, from: data)
        }
    }
#endif
