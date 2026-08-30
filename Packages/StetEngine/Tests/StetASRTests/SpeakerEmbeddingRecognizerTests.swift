import Foundation
import Testing

@testable import StetASR

@Suite("Speaker Embedding Recognizer")
struct SpeakerEmbeddingRecognizerTests {
    private let model = SpeakerEmbeddingModelIdentity(
        modelID: "3d-speaker-campplus",
        revision: "2026-08",
        dimension: 2
    )

    @Test func centroidNormalizesEveryClipBeforeAveraging() throws {
        let centroid = try SpeakerEmbeddingRecognizer.normalizedCentroid([
            [3, 4],
            [0, 2],
        ])

        #expect(abs(centroid[0] - 0.316_227_76) < 0.000_01)
        #expect(abs(centroid[1] - 0.948_683_3) < 0.000_01)
    }

    @Test func cosineMatchReturnsBestProfileAboveThresholdAndMargin() throws {
        let ownerID = UUID()
        let decision = try SpeakerEmbeddingRecognizer.match(
            embedding: [1, 0],
            voicedSampleCount: 19_200,
            sampleRate: 16_000,
            profiles: [
                reference(id: ownerID, centroid: [1, 0], threshold: 0.8),
                reference(centroid: [0, 1], threshold: 0.8),
            ],
            model: model,
            runnerUpMargin: 0.1
        )

        guard case .matched(let profileID, let similarity) = decision else {
            Issue.record("Expected a profile match, got \(decision)")
            return
        }
        #expect(profileID == ownerID)
        #expect(abs(similarity - 1) < 0.000_01)
    }

    @Test func belowThresholdMatchRemainsOther() throws {
        let decision = try SpeakerEmbeddingRecognizer.match(
            embedding: [0.6, 0.8],
            voicedSampleCount: 19_200,
            sampleRate: 16_000,
            profiles: [reference(centroid: [1, 0], threshold: 0.8)],
            model: model,
            runnerUpMargin: 0.1
        )

        guard case .other(let bestSimilarity) = decision else {
            Issue.record("Expected open-set rejection, got \(decision)")
            return
        }
        #expect(abs((bestSimilarity ?? 0) - 0.6) < 0.000_01)
    }

    @Test func closeRunnerUpRemainsUnresolved() throws {
        let decision = try SpeakerEmbeddingRecognizer.match(
            embedding: [1, 0],
            voicedSampleCount: 19_200,
            sampleRate: 16_000,
            profiles: [
                reference(centroid: [1, 0], threshold: 0.8),
                reference(centroid: [0.995, 0.1], threshold: 0.8),
            ],
            model: model,
            runnerUpMargin: 0.05
        )

        #expect(decision == .unresolved(.ambiguous))
    }

    @Test func insufficientVoicedContentRemainsUnresolved() throws {
        let decision = try SpeakerEmbeddingRecognizer.match(
            embedding: [1, 0],
            voicedSampleCount: 19_199,
            sampleRate: 16_000,
            profiles: [reference(centroid: [1, 0], threshold: 0.8)],
            model: model,
            minimumVoicedSeconds: 1.2,
            runnerUpMargin: 0.1
        )

        #expect(decision == .unresolved(.insufficientVoice))
    }

    @Test func modelRevisionMismatchRequiresReenrollment() {
        let staleModel = SpeakerEmbeddingModelIdentity(
            modelID: model.modelID,
            revision: "stale",
            dimension: model.dimension
        )

        #expect(throws: SpeakerEmbeddingRecognizerError.modelMismatch) {
            _ = try SpeakerEmbeddingRecognizer.match(
                embedding: [1, 0],
                voicedSampleCount: 19_200,
                sampleRate: 16_000,
                profiles: [reference(model: staleModel, centroid: [1, 0], threshold: 0.8)],
                model: model,
                runnerUpMargin: 0.1
            )
        }
    }

    @Test func embeddingDimensionMismatchRequiresReenrollment() {
        let wrongDimension = SpeakerEmbeddingModelIdentity(
            modelID: model.modelID,
            revision: model.revision,
            dimension: 3
        )

        #expect(throws: SpeakerEmbeddingRecognizerError.dimensionMismatch) {
            _ = try SpeakerEmbeddingRecognizer.match(
                embedding: [1, 0],
                voicedSampleCount: 19_200,
                sampleRate: 16_000,
                profiles: [reference(model: wrongDimension, centroid: [1, 0, 0], threshold: 0.8)],
                model: model,
                runnerUpMargin: 0.1
            )
        }
    }

    private func reference(
        id: UUID = UUID(),
        model: SpeakerEmbeddingModelIdentity? = nil,
        centroid: [Float],
        threshold: Double
    ) -> SpeakerEmbeddingProfileReference {
        SpeakerEmbeddingProfileReference(
            id: id,
            model: model ?? self.model,
            normalizedCentroid: centroid,
            matchThreshold: threshold
        )
    }
}
