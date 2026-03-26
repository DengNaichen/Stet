#if os(macOS)
    import Foundation
    import SwiftUI

    private final class StetVisualsBundleToken {}

    enum StetVisualsShaderLibrary {
        @available(macOS 15.0, *)
        static func cloudOrbGlassWide(
            size: CGSize,
            time: Double,
            body: Double,
            presence: Double,
            pulse: Double,
            articulation: Double,
            detail: Double,
            a: Color,
            b: Color,
            c: Color
        ) -> Shader {
            ShaderLibrary.bundle(shaderBundle).cloudOrbGlassWide(
                .float2(size.width, size.height),
                .float(time),
                .float(body),
                .float(presence),
                .float(pulse),
                .float(articulation),
                .float(detail),
                .color(a),
                .color(b),
                .color(c)
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
