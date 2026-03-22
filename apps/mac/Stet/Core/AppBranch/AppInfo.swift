import AppKit
import Foundation

/// A value type containing information about a foreground application.
///
/// AppInfo encapsulates all relevant details about a macOS application,
/// including its bundle identifier, display name, process ID, and whether
/// it represents the host application.
public struct AppInfo: Equatable {
    /// The unique bundle identifier of the application (e.g., "com.apple.Safari")
    public let bundleIdentifier: String

    /// The user-visible localized name of the application
    public let localizedName: String

    /// The process identifier (PID) of the application
    public let processIdentifier: pid_t

    /// Whether this application is the module's own host application
    public let isOwnHostApplication: Bool

    /// The full NSRunningApplication reference for this application when
    /// available from the live workspace. Tests may leave this nil.
    public let runningApplication: NSRunningApplication?

    /// Creates a new AppInfo instance.
    ///
    /// - Parameters:
    ///   - bundleIdentifier: The unique bundle identifier
    ///   - localizedName: The user-visible application name
    ///   - processIdentifier: The process ID
    ///   - isOwnHostApplication: Whether this is the host application
    ///   - runningApplication: The NSRunningApplication reference when available
    public init(
        bundleIdentifier: String,
        localizedName: String,
        processIdentifier: pid_t,
        isOwnHostApplication: Bool,
        runningApplication: NSRunningApplication?
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.localizedName = localizedName
        self.processIdentifier = processIdentifier
        self.isOwnHostApplication = isOwnHostApplication
        self.runningApplication = runningApplication
    }

    /// Compares two AppInfo instances for equality.
    ///
    /// Equality is based on the user-facing snapshot we surface from AppBranch:
    /// bundle identifier, localized name, process identifier, and host-app flag.
    public static func == (lhs: AppInfo, rhs: AppInfo) -> Bool {
        lhs.bundleIdentifier == rhs.bundleIdentifier &&
            lhs.localizedName == rhs.localizedName &&
            lhs.processIdentifier == rhs.processIdentifier &&
            lhs.isOwnHostApplication == rhs.isOwnHostApplication
    }
}

/// A callback closure that is invoked when the foreground application changes.
///
/// The callback receives an optional AppInfo representing the new foreground
/// application. A nil value indicates that no application is currently in the
/// foreground.
public typealias AppChangeCallback = (AppInfo?) -> Void

/// Represents a registered observer for application change events.
public struct AppChangeObserver {
    public let id: UUID
    public let callback: AppChangeCallback
    public let createdAt: Date

    public init(
        id: UUID,
        callback: @escaping AppChangeCallback,
        createdAt: Date
    ) {
        self.id = id
        self.callback = callback
        self.createdAt = createdAt
    }
}
