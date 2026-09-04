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

        func recentSessionDirectories(limit: Int = 20) throws -> [URL] {
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
                .prefix(limit)
                .map { $0 }
        }

        nonisolated static func folderName(for startedAt: Date) -> String {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
            return formatter.string(from: startedAt)
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
    }
#endif
