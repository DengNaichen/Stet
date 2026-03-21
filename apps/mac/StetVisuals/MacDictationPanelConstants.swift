#if os(macOS)
import SwiftUI

enum MacDictationPanelConstants {
    enum Layout {
        static let mainWidthIdle: CGFloat = 200
        static let mainWidthStarting: CGFloat = 200
        static let mainWidthListening: CGFloat = 200
        static let mainWidthProcessing: CGFloat = 200
        static let mainWidthResult: CGFloat = 200
        static let mainWidthClipboard: CGFloat = 200
        static let mainWidthError: CGFloat = 200
        
        static let controlHeight: CGFloat = 40
        static let clipboardHeight: CGFloat = 118
        static let clipboardCornerRadius: CGFloat = 30

        static let offsetXListening: CGFloat = 12
        static let offsetXAlternate: CGFloat = 24
        
        static let offsetYDefault: CGFloat = -4
        static let offsetYClipboard: CGFloat = -2
        
        static let shadowRadiusClipboard: CGFloat = 18
        static let shadowRadiusDefault: CGFloat = 8
        static let shadowOpacityClipboard: Double = 0.22
        static let shadowOpacityDefault: Double = 0.12
        static let shadowYClipboard: CGFloat = 10
        static let shadowYDefault: CGFloat = 4
    }
    
    enum VoiceReactivity {
        static let easedPower: Double = 0.45
        static let shaderDrivePower: Double = 0.82
        static let shaderDriveBoostStarting: Double = 1.08
        static let shaderDriveBoostListening: Double = 1.18
        static let shaderDriveFloorStarting: Double = 0.05
        static let shaderDriveFloorListening: Double = 0.08
        
        static let levelBaseIdle: Double = 0.10
        static let levelBaseStarting: Double = 0.15
        static let levelMultStarting: Double = 0.45
        static let levelMaxStarting: Double = 0.60
        static let levelBaseListening: Double = 0.22
        static let levelMultListening: Double = 0.78
        static let levelMaxListening: Double = 1.0
        static let levelBaseProcessing: Double = 0.08
        static let levelBaseResult: Double = 0.10
        
        static let shaderFrameIntervalActive: Double = 1.0 / 40.0
        static let shaderFrameIntervalIdle: Double = 1.0 / 30.0
    }
    
    enum Colors {
        // Base Neutral (Idle)
        static let topIdle = (0.95, 0.96, 0.98)
        static let midIdle = (0.86, 0.88, 0.90)
        static let lowIdle = (0.72, 0.74, 0.76)
        
        // Active Speaking (Blue Injection)
        static let topSpeaking = (0.35, 0.85, 1.00)
        static let midSpeaking = (0.20, 0.65, 1.00)
        static let lowSpeaking = (0.10, 0.45, 0.85)
        
        // Active Processing (Orange Injection)
        static let topProcessing = (1.00, 0.80, 0.45)
        static let midProcessing = (1.00, 0.55, 0.12)
        static let lowProcessing = (0.85, 0.32, 0.08)
    }
}

extension Color {
    static let macDictationPrimaryAction = Color(
        red: 179.0 / 255.0,
        green: 190.0 / 255.0,
        blue: 250.0 / 255.0
    )
}
#endif
