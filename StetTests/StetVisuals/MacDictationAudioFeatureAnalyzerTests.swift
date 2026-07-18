#if os(macOS)
    import AVFoundation
    import StetVisuals
    import Testing

    @Suite("Mac Dictation Audio Feature Analyzer")
    struct MacDictationAudioFeatureAnalyzerTests {
        @Test func louderSpeechLikeSignalPreservesMoreVisualEnergy() throws {
            let analyzer = try #require(MacDictationAudioFeatureAnalyzer())
            let quiet = analyzer.analyze(buffer: try makeSineBuffer(amplitude: 0.01))
            let loud = analyzer.analyze(buffer: try makeSineBuffer(amplitude: 0.20))

            #expect(loud.estimatedSummary.level > quiet.estimatedSummary.level + 0.4)
            #expect(loud.bands.reduce(0) { $0 + $1.weight } > quiet.bands.reduce(0) { $0 + $1.weight })
            #expect(abs(loud.bands.reduce(0) { $0 + $1.weight } - loud.estimatedSummary.level) < 0.001)
        }

        @Test func silenceProducesZeroVisualSignals() throws {
            let analyzer = try #require(MacDictationAudioFeatureAnalyzer())
            let signals = analyzer.analyze(buffer: try makeSineBuffer(amplitude: 0))

            #expect(signals == .zero)
        }

        private func makeSineBuffer(amplitude: Float) throws -> AVAudioPCMBuffer {
            let sampleRate = 44_100.0
            let frameCount = AVAudioFrameCount(MacDictationAudioFieldConstants.fftSize)
            let format = try #require(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1))
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount))
            let channel = try #require(buffer.floatChannelData?[0])
            buffer.frameLength = frameCount

            for index in 0..<Int(frameCount) {
                let phase = 2 * Float.pi * 440 * Float(index) / Float(sampleRate)
                channel[index] = amplitude * sin(phase)
            }
            return buffer
        }
    }
#endif
