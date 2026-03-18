@preconcurrency import AVFoundation
import Foundation

enum AudioLevelNormalizer {
    private static let minimumVisibleLevel = 0.08

    nonisolated static func normalizedLevel(from buffer: AVAudioPCMBuffer) -> Double {
        guard let channelData = buffer.floatChannelData else {
            return minimumVisibleLevel
        }

        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frameLength > 0, channelCount > 0 else {
            return minimumVisibleLevel
        }

        var sum: Float = 0

        for channel in 0..<channelCount {
            let samples = channelData[channel]

            for index in 0..<frameLength {
                let sample = samples[index]
                sum += sample * sample
            }
        }

        let meanSquare = sum / Float(frameLength * channelCount)
        let rms = sqrt(meanSquare)
        return min(max(Double(rms) * 3.2, minimumVisibleLevel), 1)
    }

    nonisolated static func normalizedPowerLevel(_ averagePower: Float) -> Double {
        guard averagePower.isFinite else {
            return minimumVisibleLevel
        }

        let clampedPower = max(averagePower, -50)
        let normalized = (clampedPower + 50) / 50
        return min(max(Double(normalized), minimumVisibleLevel), 1)
    }
}
