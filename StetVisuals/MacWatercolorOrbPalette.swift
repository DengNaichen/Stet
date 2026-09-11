#if os(macOS)
    import simd

    /// Fixed color roles shared by listening and Thinking. Theme selection never changes motion.
    struct MacWatercolorOrbPalette: Equatable {
        let groundLow: SIMD3<Float>
        let groundHigh: SIMD3<Float>
        let interlayer: SIMD3<Float>
        let lightPigment: SIMD3<Float>
        let pigment: SIMD3<Float>
        let densePigment: SIMD3<Float>

        init(theme: MacDictationShaderTheme) {
            if theme == .watercolor {
                // Preserve the approved browser's exact palette.
                groundLow = SIMD3(0.80, 0.943, 0.976)
                groundHigh = SIMD3(0.88, 0.977, 0.992)
                interlayer = SIMD3(0.998, 0.999, 0.991)
                lightPigment = SIMD3(0.075, 0.725, 0.985)
                pigment = SIMD3(0.023529, 0.631373, 0.968627)
                densePigment = SIMD3(0.012, 0.455, 0.895)
                return
            }

            // Reuse all three existing swatches: ground, interlayer, and pigment.
            // Dilution creates depth without inventing another palette or rotating colors by state.
            let source = theme.palette.idle
            let ground = SIMD3<Float>(Float(source.a.0), Float(source.a.1), Float(source.a.2))
            let ribbon = SIMD3<Float>(Float(source.b.0), Float(source.b.1), Float(source.b.2))
            let paint = SIMD3<Float>(Float(source.c.0), Float(source.c.1), Float(source.c.2))
            let paper = SIMD3<Float>(0.998, 0.999, 0.991)
            groundLow = simd_mix(ground, paper, SIMD3(repeating: 0.28))
            groundHigh = simd_mix(ground, paper, SIMD3(repeating: 0.60))
            interlayer = simd_mix(ribbon, paper, SIMD3(repeating: 0.20))
            lightPigment = simd_mix(paint, paper, SIMD3(repeating: 0.22))
            pigment = paint
            densePigment = simd_mix(paint, ground, SIMD3(repeating: 0.38))
        }
    }
#endif
