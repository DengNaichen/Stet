#if os(macOS)
    import Foundation
    import Testing

    @testable import Stet

    @Suite("Meeting Recording Store")
    struct MeetingRecordingStoreTests {
        @Test func folderNameUsesLocalStartTimestamp() {
            let startedAt = Date(timeIntervalSince1970: 1_704_067_200)
            let expected: String = {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
                return formatter.string(from: startedAt)
            }()

            #expect(MeetingRecordingStore.folderName(for: startedAt) == expected)
        }

        @Test func makeSessionDirectoryCreatesAudioTranscriptAndSessionURLs() throws {
            let root = TestSupport.temporaryDirectoryURL()
            let store = MeetingRecordingStore(rootDirectory: root)
            let startedAt = Date(timeIntervalSince1970: 1_704_067_200)
            let directory = try store.makeSessionDirectory(startedAt: startedAt)

            #expect(FileManager.default.fileExists(atPath: directory.url.path))
            #expect(directory.audioURL.lastPathComponent == "audio.wav")
            #expect(directory.transcriptURL.lastPathComponent == "transcript.md")
            #expect(directory.sessionURL.lastPathComponent == "session.json")
            #expect(directory.url.lastPathComponent == MeetingRecordingStore.folderName(for: startedAt))
        }
    }
#endif
