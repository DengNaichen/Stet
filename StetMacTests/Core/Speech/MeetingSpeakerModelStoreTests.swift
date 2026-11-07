#if os(macOS)
    import Foundation
    import Testing
    @testable import Stet

    @Suite("Meeting speaker model cache")
    struct MeetingSpeakerModelStoreTests {
        @Test func interruptedDownloadKeepsCompletedFilesAndRetriesOnlyMissingFiles() async throws {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let downloads = ModelDownloads()
            let files = [
                MeetingSpeakerModelStore.File(path: "first.bin", size: 3), .init(path: "coremldata.bin", size: 3),
            ]
            let store = MeetingSpeakerModelStore(
                directory: root, files: files,
                download: { file, destination, _ in
                    try await downloads.write(file: file.path, to: destination)
                }, validate: { _ in })
            do {
                try await store.prepare { _ in }
                Issue.record("Expected interrupted download")
            } catch {}
            #expect(!store.isComplete)
            #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("first.bin").path))
            try await store.prepare { _ in }
            #expect(store.isComplete)
            #expect(await downloads.calls == ["first.bin", "coremldata.bin", "coremldata.bin"])
        }

        @Test func loadFailureDoesNotDeleteOrRedownloadCompleteCache() async throws {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try Data([1, 2, 3]).write(to: root.appendingPathComponent("coremldata.bin"))
            let store = MeetingSpeakerModelStore(
                directory: root, files: [.init(path: "coremldata.bin", size: 3)],
                download: { _, _, _ in
                    Issue.record("A load error must not trigger another download")
                }, validate: { _ in throw CocoaError(.fileReadCorruptFile) })
            for _ in 0..<2 {
                do { try await store.prepare { _ in }; Issue.record("Expected validation error") } catch {}
                #expect(store.isComplete)
            }
        }

        @Test func directoryAndTruncatedFilesAreNotReady() throws {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let store = MeetingSpeakerModelStore(
                directory: root, files: [.init(path: "coremldata.bin", size: 3)], download: { _, _, _ in },
                validate: { _ in })
            #expect(!store.isComplete)
            try Data([1]).write(to: root.appendingPathComponent("coremldata.bin"))
            #expect(!store.isComplete)
        }
    }

    private actor ModelDownloads {
        var calls: [String] = []
        func write(file: String, to url: URL) throws {
            calls.append(file)
            if calls.count == 2 { throw URLError(.networkConnectionLost) }
            try Data([1, 2, 3]).write(to: url)
        }
    }
#endif
