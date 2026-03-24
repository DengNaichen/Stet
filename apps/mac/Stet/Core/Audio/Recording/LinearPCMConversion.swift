@preconcurrency import AVFoundation
import Foundation

enum LinearPCMConversion {
    enum ConversionError: Error {
        case outputBufferCreationFailed
        case conversionFailed
    }

    nonisolated static func makeConverter(
        from inputFormat: AVAudioFormat,
        to outputFormat: AVAudioFormat
    ) -> AVAudioConverter? {
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            return nil
        }

        // Favor startup latency for live dictation capture. The default sample
        // rate converter priming can hold onto several initial tap buffers
        // before emitting output, which shows up as ~100ms before the first
        // committed speech frames arrive.
        converter.primeMethod = .none

        if inputFormat.channelCount != outputFormat.channelCount {
            converter.downmix = true
        }

        return converter
    }

    nonisolated static func convertedFrameCapacity(
        for inputFrameCount: AVAudioFrameCount,
        inputSampleRate: Double,
        outputSampleRate: Double
    ) -> AVAudioFrameCount {
        guard inputFrameCount > 0,
            inputSampleRate > 0,
            outputSampleRate > 0,
            inputSampleRate.isFinite,
            outputSampleRate.isFinite
        else {
            return 0
        }

        let ratio = outputSampleRate / inputSampleRate
        let scaledFrameCount = ceil(Double(inputFrameCount) * ratio)
        return max(AVAudioFrameCount(scaledFrameCount) + 32, 32)
    }

    nonisolated static func convert(
        _ inputBuffer: AVAudioPCMBuffer,
        using converter: AVAudioConverter,
        outputFormat: AVAudioFormat
    ) throws -> AVAudioPCMBuffer {
        let outputFrameCapacity = convertedFrameCapacity(
            for: inputBuffer.frameLength,
            inputSampleRate: inputBuffer.format.sampleRate,
            outputSampleRate: outputFormat.sampleRate
        )
        guard
            let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity: outputFrameCapacity
            )
        else {
            throw ConversionError.outputBufferCreationFailed
        }

        var didProvideInput = false
        var conversionError: NSError?
        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
            if didProvideInput {
                outStatus.pointee = .noDataNow
                return nil
            }

            didProvideInput = true
            outStatus.pointee = .haveData
            return inputBuffer
        }

        if let conversionError {
            throw conversionError
        }

        switch status {
        case .haveData, .inputRanDry, .endOfStream:
            return outputBuffer
        case .error:
            throw ConversionError.conversionFailed
        @unknown default:
            throw ConversionError.conversionFailed
        }
    }
}
