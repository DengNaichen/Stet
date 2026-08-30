@preconcurrency import AVFoundation
import Foundation
import StetCore

@testable import Stet

final class TestPassiveClock: @unchecked Sendable {
    private let lock = NSLock()
    private var storedSample: Int64

    init(sample: Int64 = 0) {
        storedSample = sample
    }

    var sample: Int64 {
        lock.withLock { storedSample }
    }

    func advance(by sampleCount: Int64) {
        lock.withLock { storedSample += sampleCount }
    }
}

struct TestPassiveAudioFrame: Equatable, Sendable {
    let id: Int64
    let epoch: Int64
    let startSample: Int64
    let samples: [Float]

    var endSample: Int64 {
        startSample + Int64(samples.count)
    }

    static func make(
        id: Int64 = 0,
        epoch: Int64 = 0,
        startSample: Int64 = 0,
        sampleCount: Int = 1_600,
        value: Float = 0.25
    ) -> Self {
        Self(
            id: id,
            epoch: epoch,
            startSample: startSample,
            samples: Array(repeating: value, count: sampleCount)
        )
    }
}

actor TestPassiveVerifier {
    var similarities: [Double]
    private(set) var frames: [[Float]] = []

    init(similarities: [Double] = []) {
        self.similarities = similarities
    }

    func verify(_ samples: [Float]) throws -> Double {
        frames.append(samples)
        guard !similarities.isEmpty else { throw TestError.expected }
        return similarities.removeFirst()
    }
}

struct TestDiarizedRegion: Equatable, Sendable {
    let startSample: Int64
    let endSample: Int64
    let track: Int
    let activityConfidence: Double
    let isOverlap: Bool
}

actor TestPassiveDiarizer {
    var results: [[TestDiarizedRegion]]
    private(set) var frames: [[Float]] = []

    init(results: [[TestDiarizedRegion]] = []) {
        self.results = results
    }

    func diarize(_ samples: [Float]) throws -> [TestDiarizedRegion] {
        frames.append(samples)
        guard !results.isEmpty else { return [] }
        return results.removeFirst()
    }
}

actor TestPassiveNano {
    var results: [Result<String, TestError>]
    private(set) var audio: [[Float]] = []
    private(set) var fileSampleCounts: [Int] = []
    private(set) var fileURLs: [URL] = []

    init(results: [Result<String, TestError>] = []) {
        self.results = results
    }

    func transcribe(_ samples: [Float]) throws -> String {
        audio.append(samples)
        guard !results.isEmpty else { throw TestError.expected }
        return try results.removeFirst().get()
    }

    func transcribe(fileURL: URL) throws -> String {
        let file = try AVAudioFile(forReading: fileURL)
        fileSampleCounts.append(Int(file.length))
        fileURLs.append(fileURL)
        guard !results.isEmpty else { throw TestError.expected }
        return try results.removeFirst().get()
    }
}

actor TestPassiveHistory {
    enum Call: Equatable, Sendable {
        case create(UUID)
        case update(UUID, String, [CapturedSpeakerRegion])
        case finish(UUID, String, [CapturedSpeakerRegion])
        case fail(UUID, String, [CapturedSpeakerRegion])
    }

    private(set) var calls: [Call] = []

    func record(_ call: Call) {
        calls.append(call)
    }
}
