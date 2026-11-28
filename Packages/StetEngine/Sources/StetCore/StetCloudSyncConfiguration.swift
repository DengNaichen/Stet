import Foundation

public enum StetCloudSyncConfiguration {
    public static let teamIdentifierPrefix = "67BL3M4FPS."
    public static let sharedKeychainAccessGroup = "67BL3M4FPS.NaichengDeng.Stet.shared"
    public static let sharedKeychainService = "NaichengDeng.Stet.credentials"
    public static let sharedKVStoreIdentifier = "67BL3M4FPS.NaichengDeng.Stet"
    public static let cloudKitContainerIdentifier = "iCloud.NaichengDeng.Stet"
    public static let syncedStoreFilename = "SyncedData.store"
}

public extension Notification.Name {
    static let stetCloudDataDidChange = Notification.Name("StetCore.CloudDataDidChange")
}
