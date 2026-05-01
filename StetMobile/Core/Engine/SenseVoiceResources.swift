import Foundation

struct SenseVoiceResources {
    let modelPath: String
    let tokensPath: String
    let vadPath: String

    static func bundled() throws -> SenseVoiceResources {
        let bundle = Bundle.main
        guard let model = bundle.resourceURL(named: "model.int8", extension: "onnx", subdirectory: "SenseVoice") else {
            throw SenseVoiceError.missingResource("SenseVoice/model.int8.onnx or model.int8.onnx")
        }
        guard let tokens = bundle.resourceURL(named: "tokens", extension: "txt", subdirectory: "SenseVoice") else {
            throw SenseVoiceError.missingResource("SenseVoice/tokens.txt or tokens.txt")
        }
        guard let vad = bundle.resourceURL(named: "silero_vad", extension: "onnx", subdirectory: "Vad") else {
            throw SenseVoiceError.missingResource("Vad/silero_vad.onnx or silero_vad.onnx")
        }
        return SenseVoiceResources(
            modelPath: model.path,
            tokensPath: tokens.path,
            vadPath: vad.path
        )
    }
}

enum SenseVoiceError: LocalizedError {
    case missingResource(String)
    case microphoneDenied
    case invalidInputFormat
    case audioEngineUnavailable

    var errorDescription: String? {
        switch self {
        case .missingResource(let path):
            return "Missing bundled resource: \(path)"
        case .microphoneDenied:
            return "Microphone permission was denied."
        case .invalidInputFormat:
            return "Unable to create 16 kHz mono audio format."
        case .audioEngineUnavailable:
            return "Audio engine input is unavailable."
        }
    }
}

private extension Bundle {
    func resourceURL(named name: String, extension ext: String, subdirectory: String) -> URL? {
        url(forResource: name, withExtension: ext, subdirectory: subdirectory)
            ?? url(forResource: name, withExtension: ext)
    }
}
