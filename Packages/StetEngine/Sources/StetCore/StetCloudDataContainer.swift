import Combine
import CoreData
import Foundation
import OSLog
import Security
import SwiftData

public final class StetCloudDataContainer: @unchecked Sendable {
    public static let shared = StetCloudDataContainer()
    public let modelContainer: ModelContainer?
    let initializationError: Error?
    private let observation: AnyCancellable
    private static let logger = Logger(subsystem: "StetCore", category: "CloudData")

    private init() {
        do {
            modelContainer = try Self.makePersistentContainer()
            initializationError = nil
        } catch {
            modelContainer = nil
            initializationError = error
            Self.logger.error("Could not open dictation data: \(error)")
        }
        observation = NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange)
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { _ in
                MainActor.assumeIsolated {
                    NotificationCenter.default.post(name: .stetCloudDataDidChange, object: nil)
                }
            }
    }

    public static func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([HistoryEntry.self, DictationSessionRecord.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    public static func makePersistentContainer(
        appSupportDirectory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0],
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "NaichengDeng.Stet",
        cloudKitEnabled: Bool = true
    ) throws -> ModelContainer {
        let directory = appSupportDirectory.appendingPathComponent(bundleIdentifier)
            .appendingPathComponent("SwiftData", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(StetCloudSyncConfiguration.syncedStoreFilename)
        let schema = Schema([HistoryEntry.self, DictationSessionRecord.self])
        func open(_ database: ModelConfiguration.CloudKitDatabase) throws -> ModelContainer {
            let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: database)
            return try ModelContainer(for: schema, configurations: [configuration])
        }
        let container: ModelContainer
        if cloudKitEnabled && canUseCloudKit {
            do {
                container = try open(.private(StetCloudSyncConfiguration.cloudKitContainerIdentifier))
            } catch {
                logger.warning("CloudKit unavailable, opening local dictation data: \(error)")
                container = try open(.none)
            }
        } else {
            container = try open(.none)
        }
        try LegacyDictationMigration.migrate(into: container, directory: directory, appSupport: appSupportDirectory)
        return container
    }

    private static var canUseCloudKit: Bool {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return false
        }
        #if os(macOS)
            guard let task = SecTaskCreateFromSelf(nil),
                let containers = SecTaskCopyValueForEntitlement(
                    task, "com.apple.developer.icloud-container-identifiers" as CFString, nil) as? [String]
            else { return false }
            return containers.contains(StetCloudSyncConfiguration.cloudKitContainerIdentifier)
        #elseif targetEnvironment(simulator)
            return FileManager.default.ubiquityIdentityToken != nil
        #else
            return true
        #endif
    }
}
