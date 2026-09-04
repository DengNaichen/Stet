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

        @Test func conversationalSpeechLevelProducesVisibleDrive() throws {
            let analyzer = try #require(MacDictationAudioFeatureAnalyzer())
            let signals = analyzer.analyze(buffer: try makeSineBuffer(rmsDBFS: -45))

            #expect(signals.estimatedSummary.level > 0.4)
            #expect(signals.estimatedSummary.level < 0.55)
            #expect(signals.bands.reduce(0) { $0 + $1.weight } > 0.4)
        }

        @Test func signalBelowNoiseFloorStaysVisuallyQuiet() throws {
            let analyzer = try #require(MacDictationAudioFeatureAnalyzer())
            let signals = analyzer.analyze(buffer: try makeSineBuffer(rmsDBFS: -65))

            #expect(signals.estimatedSummary.level == 0)
            #expect(signals.bands.allSatisfy { $0.weight == 0 })
        }

        @Test func levelDoesNotIncludeFFTZeroPadding() throws {
            let analyzer = try #require(MacDictationAudioFeatureAnalyzer())
            let fullBuffer = analyzer.analyze(buffer: try makeSineBuffer(rmsDBFS: -45))
            let shortBuffer = analyzer.analyze(buffer: try makeSineBuffer(rmsDBFS: -45, frameCount: 512))

            #expect(abs(fullBuffer.estimatedSummary.level - shortBuffer.estimatedSummary.level) < 0.02)
        }

        private func makeSineBuffer(
            rmsDBFS: Float,
            frameCount: AVAudioFrameCount = AVAudioFrameCount(MacDictationAudioFieldConstants.fftSize)
        ) throws -> AVAudioPCMBuffer {
            let rms = pow(Float(10), rmsDBFS / 20)
            return try makeSineBuffer(amplitude: rms * sqrt(Float(2)), frameCount: frameCount)
        }

        private func makeSineBuffer(
            amplitude: Float,
            frameCount: AVAudioFrameCount = AVAudioFrameCount(MacDictationAudioFieldConstants.fftSize)
        ) throws -> AVAudioPCMBuffer {
            let sampleRate = 44_100.0
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
