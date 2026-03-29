#if os(macOS)
    import Accelerate
    import AVFoundation
    import Foundation
    import simd

    public final class MacDictationAudioFeatureAnalyzer: @unchecked Sendable {
        private let fftSize = MacDictationAudioFieldConstants.fftSize
        private let bandCount = MacDictationCapsuleVisualSignals.bandCount
        private let window: [Float]
        private let fft: vDSP.FFT<DSPSplitComplex>
        private let bandDisplayWeights: [Float]
        private let bandRanges: [(Float, Float)]

        public init?() {
            let log2n = vDSP_Length(log2(Float(MacDictationAudioFieldConstants.fftSize)))
            guard let fft = vDSP.FFT(log2n: log2n, radix: .radix2, ofType: DSPSplitComplex.self) else {
                return nil
            }

            self.fft = fft
            self.window = vDSP.window(
                ofType: Float.self,
                usingSequence: .hanningDenormalized,
                count: MacDictationAudioFieldConstants.fftSize,
                isHalfWindow: false
            )
            self.bandDisplayWeights = Self.buildGeomspace(start: 1.0, end: 2.2, count: bandCount)
            self.bandRanges = Self.buildLogBands(
                fMin: MacDictationAudioFieldConstants.minFrequency,
                fMax: MacDictationAudioFieldConstants.maxFrequency,
                bandCount: bandCount
            )
        }

        public func analyze(buffer: AVAudioPCMBuffer) -> MacDictationCapsuleVisualSignals {
            let sampleRate = Float(buffer.format.sampleRate)
            guard sampleRate > 0 else { return .zero }

            let samples = monoSamples(from: buffer)
            guard samples.contains(where: { abs($0) > 0.000_01 }) else { return .zero }

            let magnitudes = spectrumMagnitudes(samples: samples)
            let frequencies = frequencyBins(sampleRate: sampleRate, count: magnitudes.count)
            let features = computeBandFeatures(spectrumMag: magnitudes, freqs: frequencies)
            let groupedBands = summarizeGroupedBands(from: features)
            let level = groupedBands.max() ?? 0

            return MacDictationCapsuleVisualSignals(
                bands: features,
                estimatedSummary: MacDictationAudioVisualSummary(
                    level: min(level * 1.2, 1),
                    flowX: (groupedBands[2] - groupedBands[0]) * 0.12,
                    flowY: (groupedBands[3] - groupedBands[1]) * 0.12,
                    groupedBands: SIMD4<Float>(groupedBands[0], groupedBands[1], groupedBands[2], groupedBands[3])
                )
            )
        }

        private func monoSamples(from buffer: AVAudioPCMBuffer) -> [Float] {
            let frameCount = min(Int(buffer.frameLength), fftSize)
            let channelCount = Int(buffer.format.channelCount)
            guard frameCount > 0, channelCount > 0 else {
                return Array(repeating: 0, count: fftSize)
            }

            var mono = Array(repeating: Float(0), count: fftSize)

            guard let channelData = buffer.floatChannelData else {
                return mono
            }

            for channel in 0..<channelCount {
                let samples = UnsafeBufferPointer(start: channelData[channel], count: frameCount)
                for index in 0..<frameCount {
                    mono[index] += samples[index]
                }
            }

            let scale = 1 / Float(channelCount)
            for index in 0..<frameCount {
                mono[index] *= scale
                mono[index] *= window[index]
            }
            return mono
        }

        private func spectrumMagnitudes(samples: [Float]) -> [Float] {
            let halfCount = fftSize / 2
            var real = Array(repeating: Float(0), count: halfCount)
            var imaginary = Array(repeating: Float(0), count: halfCount)
            var output = Array(repeating: Float(0), count: halfCount)

            real.withUnsafeMutableBufferPointer { realPointer in
                imaginary.withUnsafeMutableBufferPointer { imaginaryPointer in
                    var splitComplex = DSPSplitComplex(
                        realp: realPointer.baseAddress!,
                        imagp: imaginaryPointer.baseAddress!
                    )

                    samples.withUnsafeBufferPointer { samplePointer in
                        samplePointer.baseAddress!.withMemoryRebound(
                            to: DSPComplex.self,
                            capacity: halfCount
                        ) { complexPointer in
                            vDSP_ctoz(complexPointer, 2, &splitComplex, 1, vDSP_Length(halfCount))
                        }
                    }

                    fft.forward(input: splitComplex, output: &splitComplex)

                    var magnitudes = Array(repeating: Float(0), count: halfCount)
                    vDSP.squareMagnitudes(splitComplex, result: &magnitudes)
                    output = magnitudes.map { sqrt($0) }
                }
            }

            return output
        }

        private func frequencyBins(sampleRate: Float, count: Int) -> [Float] {
            let nyquist = sampleRate * 0.5
            let denominator = max(Float(count - 1), 1)
            return (0..<count).map { nyquist * Float($0) / denominator }
        }

        private func computeBandFeatures(
            spectrumMag: [Float],
            freqs: [Float]
        ) -> [MacDictationAudioBandFeature] {
            var rawEnergies = Array(repeating: Float(0), count: bandCount)
            var centroids = Array(repeating: Float(0), count: bandCount)
            var totalEqualized: Float = 0

            for bandIndex in 0..<bandCount {
                let band = bandRanges[bandIndex]
                let indices = freqs.indices.filter { freqs[$0] >= band.0 && freqs[$0] < band.1 }
                guard let start = indices.first, let end = indices.last else { continue }

                let bandSlice = Array(spectrumMag[start...end])
                let energy = bandSlice.reduce(0, +)
                rawEnergies[bandIndex] = energy
                centroids[bandIndex] = computeSpectralCentroid(
                    freqs: freqs,
                    spectrum: spectrumMag,
                    start: start,
                    end: end + 1
                )
                totalEqualized += energy * bandDisplayWeights[bandIndex]
            }

            return bandRanges.enumerated().map { index, band in
                let weight: Float
                if totalEqualized <= 1e-12 {
                    weight = 0
                } else {
                    weight = (rawEnergies[index] * bandDisplayWeights[index]) / totalEqualized
                }

                return MacDictationAudioBandFeature(
                    x: Float(index + 1) / Float(bandCount + 1),
                    y: mapSpectralCentroidToY(centroidHz: centroids[index], fMin: band.0, fMax: band.1),
                    weight: weight
                )
            }
        }

        private func computeSpectralCentroid(
            freqs: [Float],
            spectrum: [Float],
            start: Int,
            end: Int
        ) -> Float {
            guard start < end else { return 0 }
            var weightedSum: Float = 0
            var total: Float = 0

            for index in start..<end {
                let value = spectrum[index]
                weightedSum += freqs[index] * value
                total += value
            }

            return total <= 1e-10 ? 0 : weightedSum / total
        }

        private func mapSpectralCentroidToY(
            centroidHz: Float,
            fMin: Float,
            fMax: Float,
            yMin: Float = 0.1,
            yMax: Float = 0.9
        ) -> Float {
            guard centroidHz > 0, fMax > fMin else { return yMin }
            let normalized = max(0, min(1, (centroidHz - fMin) / (fMax - fMin)))
            return yMin + (yMax - yMin) * normalized
        }

        private func summarizeGroupedBands(from features: [MacDictationAudioBandFeature]) -> [Float] {
            var groupedBands = Array(repeating: Float(0), count: 4)
            for (index, feature) in features.enumerated() {
                groupedBands[min(3, index / 3)] += feature.weight
            }
            return groupedBands
        }

        private static func buildGeomspace(start: Float, end: Float, count: Int) -> [Float] {
            guard count > 1 else { return [start] }
            let ratio = pow(end / start, 1 / Float(count - 1))
            return (0..<count).map { start * pow(ratio, Float($0)) }
        }

        private static func buildLogBands(
            fMin: Float,
            fMax: Float,
            bandCount: Int
        ) -> [(Float, Float)] {
            let edges = buildGeomspace(start: fMin, end: fMax, count: bandCount + 1)
            return (0..<bandCount).map { index in
                (edges[index], edges[index + 1])
            }
        }
    }
#endif
