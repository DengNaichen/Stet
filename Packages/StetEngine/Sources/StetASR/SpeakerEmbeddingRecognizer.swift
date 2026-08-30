import Foundation

public struct SpeakerEmbeddingModelIdentity: Codable, Equatable, Sendable {
    public let modelID: String
    public let revision: String
    public let dimension: Int

    public init(modelID: String, revision: String, dimension: Int) {
        self.modelID = modelID
        self.revision = revision
        self.dimension = dimension
    }
}

public struct SpeakerEmbeddingProfileReference: Equatable, Sendable {
    public let id: UUID
    public let model: SpeakerEmbeddingModelIdentity
    public let normalizedCentroid: [Float]
    public let matchThreshold: Double

    public init(
        id: UUID,
        model: SpeakerEmbeddingModelIdentity,
        normalizedCentroid: [Float],
        matchThreshold: Double
    ) {
        self.id = id
        self.model = model
        self.normalizedCentroid = normalizedCentroid
        self.matchThreshold = matchThreshold
    }
}

public enum SpeakerEmbeddingUnresolvedReason: Equatable, Sendable {
    case insufficientVoice
    case ambiguous
}

public enum SpeakerEmbeddingMatchDecision: Equatable, Sendable {
    case matched(profileID: UUID, similarity: Double)
    case other(bestSimilarity: Double?)
    case unresolved(SpeakerEmbeddingUnresolvedReason)
}

public enum SpeakerEmbeddingRecognizerError: Error, Equatable, Sendable {
    case invalidEmbedding
    case invalidSampleRate
    case modelNotFound
    case modelLoadFailed
    case modelMismatch
    case dimensionMismatch
}

public actor SpeakerEmbeddingRecognizer {
    public nonisolated let model: SpeakerEmbeddingModelIdentity

    private let extractor: SherpaOnnxSpeakerEmbeddingExtractorWrapper

    public init(
        modelURL: URL,
        modelID: String = "3d-speaker-campplus",
        revision: String,
        numThreads: Int = 1
    ) throws {
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw SpeakerEmbeddingRecognizerError.modelNotFound
        }

        var config = sherpaOnnxSpeakerEmbeddingExtractorConfig(
            model: modelURL.path,
            numThreads: max(numThreads, 1)
        )
        let extractor = withUnsafePointer(to: &config) {
            SherpaOnnxSpeakerEmbeddingExtractorWrapper(config: $0)
        }
        guard extractor.impl != nil, extractor.dim > 0 else {
            throw SpeakerEmbeddingRecognizerError.modelLoadFailed
        }

        self.extractor = extractor
        self.model = SpeakerEmbeddingModelIdentity(
            modelID: modelID,
            revision: revision,
            dimension: extractor.dim
        )
    }

    public func extractEmbedding(
        from samples: [Float],
        sampleRate: Int = 16_000,
        minimumVoicedSeconds: Double = 1.2
    ) throws -> [Float] {
        guard sampleRate > 0 else {
            throw SpeakerEmbeddingRecognizerError.invalidSampleRate
        }
        guard Double(samples.count) / Double(sampleRate) >= minimumVoicedSeconds else {
            throw SpeakerEmbeddingRecognizerError.invalidEmbedding
        }

        let stream = extractor.createStream()
        stream.acceptWaveform(samples: samples, sampleRate: sampleRate)
        stream.inputFinished()
        let embedding = extractor.compute(stream: stream)
        guard embedding.count == model.dimension else {
            throw SpeakerEmbeddingRecognizerError.dimensionMismatch
        }
        return try Self.normalized(embedding)
    }

    public nonisolated static func normalizedCentroid(_ embeddings: [[Float]]) throws -> [Float] {
        guard let dimension = embeddings.first?.count, dimension > 0 else {
            throw SpeakerEmbeddingRecognizerError.invalidEmbedding
        }

        var sum = Array(repeating: Double(0), count: dimension)
        for embedding in embeddings {
            guard embedding.count == dimension else {
                throw SpeakerEmbeddingRecognizerError.dimensionMismatch
            }
            let normalized = try normalized(embedding)
            for index in normalized.indices {
                sum[index] += Double(normalized[index])
            }
        }

        return try normalized(sum.map(Float.init))
    }

    public nonisolated static func cosineSimilarity(_ lhs: [Float], _ rhs: [Float]) throws -> Double {
        guard !lhs.isEmpty, lhs.count == rhs.count else {
            throw SpeakerEmbeddingRecognizerError.dimensionMismatch
        }
        guard lhs.allSatisfy(\.isFinite), rhs.allSatisfy(\.isFinite) else {
            throw SpeakerEmbeddingRecognizerError.invalidEmbedding
        }

        var dot = 0.0
        var lhsMagnitude = 0.0
        var rhsMagnitude = 0.0
        for index in lhs.indices {
            let left = Double(lhs[index])
            let right = Double(rhs[index])
            dot += left * right
            lhsMagnitude += left * left
            rhsMagnitude += right * right
        }
        guard lhsMagnitude > 0, rhsMagnitude > 0 else {
            throw SpeakerEmbeddingRecognizerError.invalidEmbedding
        }
        return dot / (sqrt(lhsMagnitude) * sqrt(rhsMagnitude))
    }

    public nonisolated static func match(
        embedding: [Float],
        voicedSampleCount: Int,
        sampleRate: Int,
        profiles: [SpeakerEmbeddingProfileReference],
        model: SpeakerEmbeddingModelIdentity,
        minimumVoicedSeconds: Double = 1.2,
        runnerUpMargin: Double
    ) throws -> SpeakerEmbeddingMatchDecision {
        guard sampleRate > 0 else {
            throw SpeakerEmbeddingRecognizerError.invalidSampleRate
        }
        guard Double(voicedSampleCount) / Double(sampleRate) >= minimumVoicedSeconds else {
            return .unresolved(.insufficientVoice)
        }
        guard embedding.count == model.dimension else {
            throw SpeakerEmbeddingRecognizerError.dimensionMismatch
        }

        var matches: [(profile: SpeakerEmbeddingProfileReference, similarity: Double)] = []
        for profile in profiles {
            guard profile.model.modelID == model.modelID, profile.model.revision == model.revision else {
                throw SpeakerEmbeddingRecognizerError.modelMismatch
            }
            guard profile.model.dimension == model.dimension,
                profile.normalizedCentroid.count == model.dimension
            else {
                throw SpeakerEmbeddingRecognizerError.dimensionMismatch
            }
            matches.append(
                (profile, try cosineSimilarity(embedding, profile.normalizedCentroid))
            )
        }
        matches.sort { $0.similarity > $1.similarity }

        guard let best = matches.first else {
            return .other(bestSimilarity: nil)
        }
        guard best.similarity >= best.profile.matchThreshold else {
            return .other(bestSimilarity: best.similarity)
        }
        if matches.count > 1, best.similarity - matches[1].similarity < runnerUpMargin {
            return .unresolved(.ambiguous)
        }
        return .matched(profileID: best.profile.id, similarity: best.similarity)
    }

    private nonisolated static func normalized(_ embedding: [Float]) throws -> [Float] {
        guard !embedding.isEmpty, embedding.allSatisfy(\.isFinite) else {
            throw SpeakerEmbeddingRecognizerError.invalidEmbedding
        }
        let magnitude = sqrt(embedding.reduce(0.0) { $0 + Double($1) * Double($1) })
        guard magnitude > 0 else {
            throw SpeakerEmbeddingRecognizerError.invalidEmbedding
        }
        return embedding.map { Float(Double($0) / magnitude) }
    }
}
