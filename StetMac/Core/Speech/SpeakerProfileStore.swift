import Foundation
import Security
import StetASR

extension Notification.Name {
    static let speakerProfilesDidChange = Notification.Name("speakerProfilesDidChange")
}

nonisolated enum SpeakerProfileRole: String, Codable, Sendable {
    case owner
    case known
}

nonisolated enum SpeakerProfileStatus: String, Codable, Sendable {
    case ready
    case requiresReenrollment
}

nonisolated struct SpeakerProfile: Codable, Equatable, Identifiable, Sendable {
    static let defaultMatchThreshold = 0.60
    static let legacyUncalibratedMatchThreshold = 0.70

    let id: UUID
    let displayName: String
    let role: SpeakerProfileRole
    let embeddingModelID: String
    let embeddingModelRevision: String
    let embeddingDimension: Int
    let normalizedCentroid: [Float]
    let enrollmentSampleCount: Int
    let matchThreshold: Double
    let createdAt: Date
    let updatedAt: Date
    var status: SpeakerProfileStatus

    nonisolated var model: SpeakerEmbeddingModelIdentity {
        SpeakerEmbeddingModelIdentity(
            modelID: embeddingModelID,
            revision: embeddingModelRevision,
            dimension: embeddingDimension
        )
    }

    nonisolated init(
        id: UUID = UUID(),
        displayName: String,
        role: SpeakerProfileRole,
        model: SpeakerEmbeddingModelIdentity,
        normalizedCentroid: [Float],
        enrollmentSampleCount: Int,
        matchThreshold: Double,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        status: SpeakerProfileStatus = .ready
    ) {
        self.id = id
        self.displayName = displayName
        self.role = role
        embeddingModelID = model.modelID
        embeddingModelRevision = model.revision
        embeddingDimension = model.dimension
        self.normalizedCentroid = normalizedCentroid
        self.enrollmentSampleCount = enrollmentSampleCount
        self.matchThreshold = matchThreshold
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.status = status
    }
}

nonisolated enum SpeakerProfileStoreError: Error, Equatable, Sendable {
    case invalidProfile
    case invalidStoredData
    case ownerAlreadyExists
    case profileLimitReached
    case keychain(operation: String, status: OSStatus)
}

actor SpeakerProfileStore {
    private let loadData: @Sendable () throws -> Data?
    private let saveData: @Sendable (Data) throws -> Void
    private let deleteData: @Sendable () throws -> Void

    init(
        serviceName: String = Bundle.main.bundleIdentifier ?? "com.openwhispr.Stet",
        loadData: (@Sendable () throws -> Data?)? = nil,
        saveData: (@Sendable (Data) throws -> Void)? = nil,
        deleteData: (@Sendable () throws -> Void)? = nil
    ) {
        self.loadData =
            loadData ?? {
                try SpeakerProfileKeychain.load(serviceName: serviceName)
            }
        self.saveData =
            saveData ?? { data in
                try SpeakerProfileKeychain.save(data, serviceName: serviceName)
            }
        self.deleteData =
            deleteData ?? {
                try SpeakerProfileKeychain.delete(serviceName: serviceName)
            }
    }

    func loadProfiles(
        currentModel: SpeakerEmbeddingModelIdentity? = nil
    ) throws -> [SpeakerProfile] {
        var profiles = try decodedProfiles()
        guard let currentModel else { return profiles }

        var changed = false
        for index in profiles.indices where profiles[index].status == .ready {
            if profiles[index].model != currentModel
                || profiles[index].matchThreshold == SpeakerProfile.legacyUncalibratedMatchThreshold
            {
                profiles[index].status = .requiresReenrollment
                changed = true
            }
        }
        if changed {
            try persist(profiles)
        }
        return profiles
    }

    func save(_ profile: SpeakerProfile) throws {
        try Self.validate(profile)
        var profiles = try decodedProfiles()
        profiles.removeAll { $0.id == profile.id }

        if profile.role == .owner, profiles.contains(where: { $0.role == .owner }) {
            throw SpeakerProfileStoreError.ownerAlreadyExists
        }
        if profile.role == .known, profiles.filter({ $0.role == .known }).count >= 3 {
            throw SpeakerProfileStoreError.profileLimitReached
        }
        guard profiles.count < 4 else {
            throw SpeakerProfileStoreError.profileLimitReached
        }

        profiles.append(profile)
        try persist(profiles)
        NotificationCenter.default.post(name: .speakerProfilesDidChange, object: nil)
    }

    func delete(id: UUID) throws {
        var profiles = try decodedProfiles()
        let previousCount = profiles.count
        profiles.removeAll { $0.id == id }
        guard profiles.count != previousCount else { return }

        if profiles.isEmpty {
            try deleteData()
        } else {
            try persist(profiles)
        }
        NotificationCenter.default.post(name: .speakerProfilesDidChange, object: nil)
    }

    func deleteAll() throws {
        try deleteData()
        NotificationCenter.default.post(name: .speakerProfilesDidChange, object: nil)
    }

    private func decodedProfiles() throws -> [SpeakerProfile] {
        guard let data = try loadData() else { return [] }
        let profiles: [SpeakerProfile]
        do {
            profiles = try JSONDecoder().decode([SpeakerProfile].self, from: data)
        } catch {
            throw SpeakerProfileStoreError.invalidStoredData
        }
        do {
            try profiles.forEach(Self.validate)
        } catch {
            throw SpeakerProfileStoreError.invalidStoredData
        }
        guard profiles.count <= 4,
            profiles.filter({ $0.role == .owner }).count <= 1,
            profiles.filter({ $0.role == .known }).count <= 3
        else {
            throw SpeakerProfileStoreError.invalidStoredData
        }
        return profiles
    }

    private func persist(_ profiles: [SpeakerProfile]) throws {
        do {
            try saveData(JSONEncoder().encode(profiles))
        } catch let error as SpeakerProfileStoreError {
            throw error
        } catch {
            throw SpeakerProfileStoreError.invalidStoredData
        }
    }

    private nonisolated static func validate(_ profile: SpeakerProfile) throws {
        guard !profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !profile.embeddingModelID.isEmpty,
            !profile.embeddingModelRevision.isEmpty,
            profile.embeddingDimension > 0,
            profile.normalizedCentroid.count == profile.embeddingDimension,
            profile.normalizedCentroid.allSatisfy(\.isFinite),
            profile.enrollmentSampleCount > 0,
            profile.matchThreshold.isFinite,
            (-1.0...1.0).contains(profile.matchThreshold)
        else {
            throw SpeakerProfileStoreError.invalidProfile
        }

        let magnitude = sqrt(
            profile.normalizedCentroid.reduce(0.0) { $0 + Double($1) * Double($1) }
        )
        guard abs(magnitude - 1) <= 0.001 else {
            throw SpeakerProfileStoreError.invalidProfile
        }
    }
}

nonisolated enum SpeakerProfileKeychain {
    static let account = "speaker-profiles"

    nonisolated static func baseQuery(serviceName: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    nonisolated static func load(serviceName: String) throws -> Data? {
        var query = baseQuery(serviceName: serviceName)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw SpeakerProfileStoreError.invalidStoredData
            }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw SpeakerProfileStoreError.keychain(operation: "load", status: status)
        }
    }

    nonisolated static func save(_ data: Data, serviceName: String) throws {
        let query = baseQuery(serviceName: serviceName)
        let update = [kSecValueData as String: data]
        var status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(add as CFDictionary, nil)
            if status == errSecDuplicateItem {
                status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
            }
        }
        guard status == errSecSuccess else {
            throw SpeakerProfileStoreError.keychain(operation: "save", status: status)
        }
    }

    nonisolated static func delete(serviceName: String) throws {
        let status = SecItemDelete(baseQuery(serviceName: serviceName) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SpeakerProfileStoreError.keychain(operation: "delete", status: status)
        }
    }
}
