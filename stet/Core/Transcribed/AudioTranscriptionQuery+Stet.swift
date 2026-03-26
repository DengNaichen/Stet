import Foundation
import OpenAI

extension AudioTranscriptionQuery.FileType {
    init?(fileURL: URL) {
        switch fileURL.pathExtension.lowercased() {
        case "flac":
            self = .flac
        case "m4a":
            self = .m4a
        case "mp3":
            self = .mp3
        case "mp4":
            self = .mp4
        case "mpeg":
            self = .mpeg
        case "mpga":
            self = .mpga
        case "ogg":
            self = .ogg
        case "wav":
            self = .wav
        case "webm":
            self = .webm
        default:
            return nil
        }
    }

    var stetFileName: String {
        switch self {
        case .mpga:
            return "speech.mp3"
        default:
            return "speech.\(rawValue)"
        }
    }

    var stetContentType: String {
        switch self {
        case .flac:
            return "audio/flac"
        case .m4a:
            return "audio/m4a"
        case .mp3, .mpga:
            return "audio/mp3"
        case .mp4:
            return "audio/mp4"
        case .mpeg:
            return "audio/mpeg"
        case .ogg:
            return "audio/ogg"
        case .wav:
            return "audio/wav"
        case .webm:
            return "audio/webm"
        }
    }
}
