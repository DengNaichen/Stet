import Foundation

enum ASREngineType: String, CaseIterable, Identifiable {
    case apple = "Apple Speech"
    case sherpa = "Sherpa-Onnx"
    var id: String { self.rawValue }
}

class ASREngineManager {
    static func makeEngine(type: ASREngineType? = nil) -> ASREngine {
        let selectedType: ASREngineType
        
        if let type = type {
            selectedType = type
        } else {
            if #available(iOS 26.0, *) {
                selectedType = .apple
            } else {
                selectedType = .sherpa
            }
        }
        
        switch selectedType {
        case .apple:
            if #available(iOS 26.0, *) {
                return AppleSpeechASREngine()
            } else {
                return SherpaOnnxASREngine()
            }
        case .sherpa:
            return SherpaOnnxASREngine()
        }
    }
}
