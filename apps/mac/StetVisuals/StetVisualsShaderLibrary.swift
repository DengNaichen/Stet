#if os(macOS)
import Foundation
import SwiftUI

private final class StetVisualsBundleToken {}

enum StetVisualsShaderLibrary {
    @available(macOS 15.0, *)
    static func cloudOrbGlassWide(
        size: CGSize,
        time: Double,
        audio: Double,
        detail: Double,
        top: Color,
        mid: Color,
        low: Color
    ) -> Shader {
        ShaderLibrary.bundle(shaderBundle).cloudOrbGlassWide(
            .float2(size.width, size.height),
            .float(time),
            .float(audio),
            .float(detail),
            .color(top),
            .color(mid),
            .color(low)
        )
    }

    private static let shaderBundle: Bundle = {
        let frameworkBundle = Bundle(for: StetVisualsBundleToken.self)
        if frameworkBundle.url(forResource: "default", withExtension: "metallib") != nil {
            return frameworkBundle
        }

        return .main
    }()
}
#endif
