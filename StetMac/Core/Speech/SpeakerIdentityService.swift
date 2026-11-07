#if os(macOS)
    import Foundation
    import StetASR
    import StetCore

    nonisolated struct SpeakerMatch: Equatable, Sendable {
        let identity: CapturedSpeakerIdentity
        let similarity: Double?
    }

    actor SpeakerIdentityService {
        private let profileStore: SpeakerProfileStore
        private let modelManager: SpeakerEmbeddingModelManager
        init(
            profileStore: SpeakerProfileStore,
            modelManager: SpeakerEmbeddingModelManager
        ) {
            self.profileStore = profileStore
            self.modelManager = modelManager
        }

        func identify(_ samples: [Float]) async throws -> SpeakerMatch {
            let recognizer = try await modelManager.recognizer()
            let profiles = try await profileStore.loadProfiles(currentModel: recognizer.model)
                .filter { $0.status == .ready }
            return try await match(
                samples,
                profiles: profiles,
                recognizer: recognizer,
                runnerUpMargin: 0.08
            )
        }

        private func match(
            _ samples: [Float],
            profiles: [SpeakerProfile],
            recognizer: SpeakerEmbeddingRecognizer,
            runnerUpMargin: Double
        ) async throws -> SpeakerMatch {
            let embedding: [Float]
            do {
                embedding = try await recognizer.extractEmbedding(from: samples)
            } catch SpeakerEmbeddingRecognizerError.invalidEmbedding {
                return SpeakerMatch(identity: .unresolved, similarity: nil)
            }
            let decision = try SpeakerEmbeddingRecognizer.match(
                embedding: embedding,
                voicedSampleCount: samples.count,
                sampleRate: 16_000,
                profiles: profiles.map {
                    SpeakerEmbeddingProfileReference(
                        id: $0.id,
                        model: $0.model,
                        normalizedCentroid: $0.normalizedCentroid,
                        matchThreshold: $0.matchThreshold
                    )
                },
                model: recognizer.model,
                runnerUpMargin: runnerUpMargin
            )
            switch decision {
            case .matched(let profileID, let similarity):
                guard let profile = profiles.first(where: { $0.id == profileID }) else {
                    return SpeakerMatch(identity: .unresolved, similarity: similarity)
                }
                let identity: CapturedSpeakerIdentity =
                    profile.role == .owner
                    ? .self
                    : .known(profileID: profile.id, displayName: profile.displayName)
                return SpeakerMatch(identity: identity, similarity: similarity)
            case .other(let similarity):
                return SpeakerMatch(identity: .other, similarity: similarity)
            case .unresolved:
                return SpeakerMatch(identity: .unresolved, similarity: nil)
            }
        }
    }

#endif
