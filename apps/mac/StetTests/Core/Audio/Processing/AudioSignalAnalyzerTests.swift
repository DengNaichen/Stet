#if os(macOS)
    import Foundation
    import Testing

    @testable import Stet

    @Suite("Audio Signal Analyzer")
    struct AudioSignalAnalyzerTests {
        @Test func analyzeSilenceDetectsNoSpeech() async throws {
            let samples = Array(repeating: Float(0), count: 16_000)

            let analysis = try await AudioSignalAnalyzer.analyze(
                samples: samples,
                sampleRate: 16_000
            )

            #expect(analysis.shouldDiscardAsNoSpeech)
            #expect(analysis.speechFrameRatio == 0)
        }

        @Test func analyzeStationaryNoiseDetectsNoSpeech() async throws {
            let samples = makeStationaryNoiseSamples(count: 16_000)

            let analysis = try await AudioSignalAnalyzer.analyze(
                samples: samples,
                sampleRate: 16_000
            )

            #expect(analysis.shouldDiscardAsNoSpeech)
        }

        @Test func analyzeSpeechDetectsSpeechPresence() async throws {
            let samples = makeSpeechLikeSamples(count: 16_000, amplitude: 0.15)

            let analysis = try await AudioSignalAnalyzer.analyze(
                samples: samples,
                sampleRate: 16_000
            )

            #expect(!analysis.shouldDiscardAsNoSpeech)
            #expect(analysis.speechFrameRatio > 0)
        }

        @Test func analyzeCalculatesNoiseFloor() async throws {
            let samples = makeStationaryNoiseSamples(count: 16_000)

            let analysis = try await AudioSignalAnalyzer.analyze(
                samples: samples,
                sampleRate: 16_000
            )

            #expect(analysis.noiseFloorDBFS < 0)
            #expect(analysis.noiseFloorDBFS > -80)
        }

        @Test func analyzeCalculatesSpeechLevel() async throws {
            let samples = makeSpeechLikeSamples(count: 16_000, amplitude: 0.15)

            let analysis = try await AudioSignalAnalyzer.analyze(
                samples: samples,
                sampleRate: 16_000
            )

            #expect(analysis.speechLevelP75DBFS < 0)
            #expect(analysis.speechLevelP75DBFS > -60)
        }

        private func makeStationaryNoiseSamples(count: Int) -> [Float] {
            var state: UInt32 = 0x1234_ABCD
            return (0..<count).map { index in
                state = 1_664_525 &* state &+ 1_013_904_223
                let white = Double(Int32(bitPattern: state)) / Double(Int32.max)
                let t = Double(index) / 16_000.0
                let hum = 0.3 * sin(2 * .pi * 90.0 * t)
                return Float(0.015 * white + 0.02 * hum)
            }
        }

        private func makeSpeechLikeSamples(count: Int, amplitude: Float) -> [Float] {
            let speechRange = 2_400..<(count - 2_400)
            var samples = Array(repeating: Float(0), count: count)

            for index in speechRange {
                let t = Double(index) / 16_000.0
                let envelope = 0.55 + 0.45 * sin(2 * .pi * 2.5 * t)
                let carrier =
                    0.72 * sin(2 * .pi * 175.0 * t)
                    + 0.22 * sin(2 * .pi * 350.0 * t)
                samples[index] = amplitude * Float(envelope) * Float(carrier)
            }

            return samples
        }
    }
#endif
