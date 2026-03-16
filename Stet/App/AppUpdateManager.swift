#if os(macOS)
import AppKit
import Combine
import Foundation
import Sparkle

@MainActor
final class AppUpdateManager: NSObject, ObservableObject, SPUStandardUserDriverDelegate, SPUUpdaterDelegate {
    enum State: Equatable {
        case unavailable(String)
        case idle
        case checking
        case upToDate(version: String)
        case updateAvailable(currentVersion: String, latestVersion: String)
        case failed(String)
    }

    @Published private(set) var state: State
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = false
    @Published private(set) var automaticallyDownloadsUpdates = false

    let configuredFeedURLString: String?

    private lazy var updaterController: SPUStandardUpdaterController? = {
        guard configurationIssue == nil else {
            return nil
        }

        return SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: self
        )
    }()

    override init() {
        let infoDictionary = Bundle.main.infoDictionary ?? [:]
        let feedURLString = (infoDictionary["SUFeedURL"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty
        configuredFeedURLString = feedURLString

        if let configurationIssue = Self.configurationIssue(in: infoDictionary) {
            state = .unavailable(configurationIssue)
        } else {
            state = .idle
        }

        super.init()

        if updaterController != nil {
            syncFromUpdater()
        }
    }

    var supportsGentleScheduledUpdateReminders: Bool { true }

    var isChecking: Bool {
        if case .checking = state {
            return true
        }

        return false
    }

    var isConfigured: Bool {
        configurationIssue == nil
    }

    var statusLabel: String {
        switch state {
        case .unavailable:
            return "Unavailable"
        case .idle:
            return "Ready"
        case .checking:
            return "Checking"
        case .upToDate:
            return "Up to Date"
        case .updateAvailable:
            return "Update Available"
        case .failed:
            return "Check Failed"
        }
    }

    var statusTint: NSColor {
        switch state {
        case .unavailable:
            return .secondaryLabelColor
        case .idle:
            return .systemBlue
        case .checking:
            return .systemBlue
        case .upToDate:
            return .systemGreen
        case .updateAvailable:
            return .systemOrange
        case .failed:
            return .systemRed
        }
    }

    var detailText: String? {
        switch state {
        case .unavailable(let message), .failed(let message):
            return message
        case .idle:
            return configuredFeedURLString.map { "Sparkle is configured with appcast \($0)." }
        case .checking:
            return "Sparkle is checking the configured appcast feed."
        case .upToDate(let version):
            return "Current version \(version) is up to date."
        case .updateAvailable(let currentVersion, let latestVersion):
            return "Current version \(currentVersion), latest appcast version \(latestVersion)."
        }
    }

    func checkForUpdates() {
        guard let updater = updaterController?.updater else {
            state = .unavailable(configurationIssue ?? "Sparkle is not configured for this build.")
            return
        }

        syncFromUpdater()
        guard updater.canCheckForUpdates else {
            state = .failed("Sparkle is currently unable to check for updates.")
            return
        }

        state = .checking
        updater.checkForUpdates()
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        guard let updater = updaterController?.updater else { return }
        updater.automaticallyChecksForUpdates = enabled
        syncFromUpdater()
    }

    func setAutomaticallyDownloadsUpdates(_ enabled: Bool) {
        guard let updater = updaterController?.updater else { return }
        updater.automaticallyDownloadsUpdates = enabled
        syncFromUpdater()
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        let nsError = error as NSError
        if Self.isNoUpdateFoundError(nsError) {
            state = .upToDate(version: currentVersionString)
            return
        }

        state = .failed(nsError.localizedDescription)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        state = .upToDate(version: currentVersionString)
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        state = .updateAvailable(
            currentVersion: currentVersionString,
            latestVersion: item.displayVersionString
        )
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        syncFromUpdater()

        guard let error else {
            return
        }

        let nsError = error as NSError
        if Self.isNoUpdateFoundError(nsError) {
            state = .upToDate(version: currentVersionString)
        } else {
            state = .failed(nsError.localizedDescription)
        }
    }

    private var configurationIssue: String? {
        Self.configurationIssue(in: Bundle.main.infoDictionary ?? [:])
    }

    private var currentVersionString: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty ?? "0"
    }

    private func syncFromUpdater() {
        guard let updater = updaterController?.updater else { return }
        canCheckForUpdates = updater.canCheckForUpdates
        automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
        automaticallyDownloadsUpdates = updater.automaticallyDownloadsUpdates
    }

    static func configurationIssue(in infoDictionary: [String: Any]) -> String? {
        let shortVersion = (infoDictionary["CFBundleShortVersionString"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty
        let buildVersion = (infoDictionary["CFBundleVersion"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty
        let feedURLString = (infoDictionary["SUFeedURL"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty
        let publicKey = (infoDictionary["SUPublicEDKey"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty

        if shortVersion == nil || buildVersion == nil {
            return "Sparkle requires CFBundleShortVersionString and CFBundleVersion."
        }

        if feedURLString == nil {
            return "Sparkle is disabled because SUFeedURL is missing. Set SPARKLE_FEED_URL in the build settings."
        }

        if publicKey == nil {
            return "Sparkle is disabled because SUPublicEDKey is missing. Set SPARKLE_PUBLIC_ED_KEY in the build settings."
        }

        guard let feedURLString,
              let feedURL = URL(string: feedURLString),
              feedURL.scheme != nil,
              feedURL.host != nil else {
            return "Sparkle is disabled because SUFeedURL is invalid."
        }

        return nil
    }

    static func isNoUpdateFoundError(_ error: NSError) -> Bool {
        error.domain == SUSparkleErrorDomain && error.code == 1001
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
#endif
