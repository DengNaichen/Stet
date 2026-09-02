#if os(macOS)
    import Foundation
    import Security
    import StetASR
    import Testing

    @testable import Stet

    @Suite("Speaker Profile Store")
    struct SpeakerProfileStoreTests {
        private let model = SpeakerEmbeddingModelIdentity(
            modelID: "3d-speaker-campplus",
            revision: "2026-08",
            dimension: 2
        )

        @Test func storesOneOwnerAndThreeKnownProfiles() async throws {
            let persistence = InMemorySpeakerProfilePersistence()
            let store = persistence.makeStore()

            try await store.save(profile(role: .owner, name: "Me"))
            await #expect(throws: SpeakerProfileStoreError.ownerAlreadyExists) {
                try await store.save(profile(role: .owner, name: "Also me"))
            }
            for name in ["A", "B", "C"] {
                try await store.save(profile(role: .known, name: name))
            }

            let profiles = try await store.loadProfiles()
            #expect(profiles.count == 4)
            #expect(profiles.filter { $0.role == .owner }.count == 1)
            #expect(profiles.filter { $0.role == .known }.count == 3)
            await #expect(throws: SpeakerProfileStoreError.profileLimitReached) {
                try await store.save(profile(role: .known, name: "D"))
            }
        }

        @Test func keychainQueryIsLocalAndNonSynchronizing() {
            let query = SpeakerProfileKeychain.baseQuery(serviceName: "com.stet.tests")

            #expect(query[kSecAttrService as String] as? String == "com.stet.tests")
            #expect(query[kSecAttrAccount as String] as? String == "speaker-profiles")
            #expect(query[kSecAttrSynchronizable as String] as? Bool == false)
            #expect(query[kSecUseDataProtectionKeychain as String] as? Bool == true)
        }

        @Test func deletesOneProfileOrTheWholeKeychainItem() async throws {
            let persistence = InMemorySpeakerProfilePersistence()
            let store = persistence.makeStore()
            let owner = profile(role: .owner, name: "Me", centroid: [1, 0])
            let known = profile(role: .known, name: "A", centroid: [0, 1])
            try await store.save(owner)
            try await store.save(known)

            try await store.delete(id: owner.id)

            #expect(try await store.loadProfiles() == [known])
            #expect(!String(decoding: try #require(persistence.data), as: UTF8.self).contains(owner.id.uuidString))

            try await store.deleteAll()

            #expect(persistence.data == nil)
        }

        @Test func persistsOnlyAggregateProfileData() async throws {
            let persistence = InMemorySpeakerProfilePersistence()
            let store = persistence.makeStore()
            try await store.save(profile(role: .owner, name: "Me"))

            let data = try #require(persistence.data)
            let json = try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
            let keys = try #require(json.first).keys

            #expect(
                Set(keys) == [
                    "id", "displayName", "role", "embeddingModelID", "embeddingModelRevision",
                    "embeddingDimension", "normalizedCentroid", "enrollmentSampleCount",
                    "matchThreshold", "createdAt", "updatedAt", "status",
                ])
        }

        @Test func marksMismatchedModelsForReenrollment() async throws {
            let persistence = InMemorySpeakerProfilePersistence()
            let store = persistence.makeStore()
            let staleModel = SpeakerEmbeddingModelIdentity(
                modelID: model.modelID,
                revision: "stale",
                dimension: model.dimension
            )
            try await store.save(profile(role: .owner, name: "Me", model: staleModel))

            let profiles = try await store.loadProfiles(currentModel: model)

            #expect(profiles.map(\.status) == [.requiresReenrollment])
            #expect(try await store.loadProfiles().map(\.status) == [.requiresReenrollment])
        }

        @Test func marksLegacyUncalibratedProfilesForReenrollment() async throws {
            let persistence = InMemorySpeakerProfilePersistence()
            let store = persistence.makeStore()
            try await store.save(profile(role: .owner, name: "Me", model: model))

            let profiles = try await store.loadProfiles(currentModel: model)

            #expect(profiles.map(\.status) == [.requiresReenrollment])
            #expect(try await store.loadProfiles().map(\.status) == [.requiresReenrollment])
        }

        @Test func rejectsInvalidCentroidMetadata() async {
            let persistence = InMemorySpeakerProfilePersistence()
            let store = persistence.makeStore()

            await #expect(throws: SpeakerProfileStoreError.invalidProfile) {
                try await store.save(profile(role: .owner, name: "Me", centroid: [1]))
            }
            await #expect(throws: SpeakerProfileStoreError.invalidProfile) {
                try await store.save(profile(role: .owner, name: "Me", centroid: [1, 1]))
            }
        }

        private func profile(
            role: SpeakerProfileRole,
            name: String,
            model: SpeakerEmbeddingModelIdentity? = nil,
            centroid: [Float] = [1, 0]
        ) -> SpeakerProfile {
            SpeakerProfile(
                id: UUID(),
                displayName: name,
                role: role,
                model: model ?? self.model,
                normalizedCentroid: centroid,
                enrollmentSampleCount: 3,
                matchThreshold: 0.7,
                createdAt: Date(timeIntervalSince1970: 1),
                updatedAt: Date(timeIntervalSince1970: 2)
            )
        }
    }

    private final class InMemorySpeakerProfilePersistence: @unchecked Sendable {
        private let lock = NSLock()
        private var storedData: Data?

        var data: Data? {
            lock.withLock { storedData }
        }

        func makeStore() -> SpeakerProfileStore {
            SpeakerProfileStore(
                loadData: { self.data },
                saveData: { data in self.lock.withLock { self.storedData = data } },
                deleteData: { self.lock.withLock { self.storedData = nil } }
            )
        }
    }
#endif
