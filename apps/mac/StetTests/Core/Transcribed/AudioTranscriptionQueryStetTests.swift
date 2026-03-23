import Foundation
import OpenAI
import Testing

@testable import Stet

@Suite("Audio Transcription Query Stet")
struct AudioTranscriptionQueryStetTests {
    @Test(arguments: [
        ("clip.flac", AudioTranscriptionQuery.FileType.flac),
        ("clip.M4A", .m4a),
        ("clip.mp3", .mp3),
        ("clip.mp4", .mp4),
        ("clip.mpeg", .mpeg),
        ("clip.mpga", .mpga),
        ("clip.ogg", .ogg),
        ("clip.wav", .wav),
        ("clip.webm", .webm)
    ])
    func fileTypeInitializerRecognizesSupportedExtensions(
        _ fileName: String,
        expectedType: AudioTranscriptionQuery.FileType
    ) {
        let fileURL = URL(fileURLWithPath: "/tmp/\(fileName)")

        #expect(AudioTranscriptionQuery.FileType(fileURL: fileURL) == expectedType)
    }

    @Test func fileTypeInitializerRejectsUnsupportedExtension() {
        let fileURL = URL(fileURLWithPath: "/tmp/clip.aiff")

        #expect(AudioTranscriptionQuery.FileType(fileURL: fileURL) == nil)
    }

    @Test(arguments: [
        (AudioTranscriptionQuery.FileType.flac, "speech.flac", "audio/flac"),
        (.m4a, "speech.m4a", "audio/m4a"),
        (.mp3, "speech.mp3", "audio/mp3"),
        (.mp4, "speech.mp4", "audio/mp4"),
        (.mpeg, "speech.mpeg", "audio/mpeg"),
        (.mpga, "speech.mp3", "audio/mp3"),
        (.ogg, "speech.ogg", "audio/ogg"),
        (.wav, "speech.wav", "audio/wav"),
        (.webm, "speech.webm", "audio/webm")
    ])
    func stetMetadataMatchesExpectedFileNameAndContentType(
        _ fileType: AudioTranscriptionQuery.FileType,
        expectedFileName: String,
        expectedContentType: String
    ) {
        #expect(fileType.stetFileName == expectedFileName)
        #expect(fileType.stetContentType == expectedContentType)
    }
}
