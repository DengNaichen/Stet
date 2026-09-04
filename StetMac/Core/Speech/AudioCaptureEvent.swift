import Foundation

nonisolated struct AudioCaptureFrameID: Hashable, Sendable {
    let epoch: UInt64
    let startSample: Int64
    let endSample: Int64
}

nonisolated struct AudioCaptureFrame: Equatable, Sendable {
    static let sampleRate = 16_000

    let epoch: UInt64
    let startSample: Int64
    let samples: [Float]

    var endSample: Int64 {
        startSample + Int64(samples.count)
    }

    var id: AudioCaptureFrameID {
        AudioCaptureFrameID(epoch: epoch, startSample: startSample, endSample: endSample)
    }

    func split(at boundary: Int64) -> (before: AudioCaptureFrame?, after: AudioCaptureFrame?) {
        guard boundary > startSample else { return (nil, self) }
        guard boundary < endSample else { return (self, nil) }

        let index = Int(boundary - startSample)
        return (
            AudioCaptureFrame(epoch: epoch, startSample: startSample, samples: Array(samples[..<index])),
            AudioCaptureFrame(epoch: epoch, startSample: boundary, samples: Array(samples[index...]))
        )
    }
}
