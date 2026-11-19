#if os(macOS)
    import AppKit
    import Combine
    import Foundation

    import Sparkle

    @MainActor
    final class AppUpdateManager: NSObject, ObservableObject, MacAppUpdateCoordinating, SPUStandardUserDriverDelegate,
        SPUUpdaterDelegate
    {
        typealias State = MacAppUpdateState

        @Published private(set) var state: State
        @Published private(set) var canCheckForUpdates = false
        @Published private(set) var automaticallyChecksForUpdates = true

        private var presentedUpdateWindowIDs: Set<ObjectIdentifier> = []

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
            if let configurationIssue = Self.configurationIssue(in: infoDictionary) {
                state = .unavailable(configurationIssue)
            } else {
                state = .idle
            }

            super.init()

            observeSparkleWindows()

            if updaterController != nil {
                configureUpdaterDefaults()
                syncFromUpdater()
            }
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        var updateSnapshot: MacAppUpdateSnapshot {
            MacAppUpdateSnapshot(
                state: state, isConfigured: isConfigured,
                canCheckForUpdates: canCheckForUpdates,
                automaticallyChecksForUpdates: automaticallyChecksForUpdates
            )
        }

        var updateSnapshots: AnyPublisher<MacAppUpdateSnapshot, Never> {
            $state.combineLatest($canCheckForUpdates, $automaticallyChecksForUpdates)
                .map { [self] state, canCheck, automaticallyChecks in
                    MacAppUpdateSnapshot(
                        state: state, isConfigured: isConfigured,
                        canCheckForUpdates: canCheck, automaticallyChecksForUpdates: automaticallyChecks
                    )
                }
                .eraseToAnyPublisher()
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
            pruneHiddenUpdateWindowIDs()
            Self.activateAppForUpdatePresentation()
            updater.checkForUpdates()
            DispatchQueue.main.async { [weak self] in
                self?.presentVisibleSparkleWindows()
            }
        }

        func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
            guard let updater = updaterController?.updater else { return }
            updater.automaticallyChecksForUpdates = enabled
            syncFromUpdater()
        }

        func standardUserDriverWillShowModalAlert() {
            Self.activateAppForUpdatePresentation()
        }

        func standardUserDriverDidShowModalAlert() {
            DispatchQueue.main.async { [weak self] in
                self?.presentModalAlertWindow()
            }
        }

        func standardUserDriverWillHandleShowingUpdate(
            _ handleShowingUpdate: Bool,
            forUpdate update: SUAppcastItem,
            state: SPUUserUpdateState
        ) {
            guard handleShowingUpdate else { return }
            pruneHiddenUpdateWindowIDs()
            Self.activateAppForUpdatePresentation()
            DispatchQueue.main.async { [weak self] in
                self?.presentVisibleSparkleWindows()
            }
        }

        func updater(_ updater: SPUUpdater, willDownloadUpdate item: SUAppcastItem, with request: NSMutableURLRequest) {
            pruneHiddenUpdateWindowIDs()
            DispatchQueue.main.async { [weak self] in
                self?.presentVisibleSparkleWindows()
            }
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

        func updater(
            _ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?
        ) {
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

        private func configureUpdaterDefaults() {
            guard let updater = updaterController?.updater else { return }
            // Sparkle persists the user's automatic-download choice in its standard
            // preferences. Do not overwrite it when the app starts.
            updater.automaticallyChecksForUpdates = true
        }

        private func observeSparkleWindows() {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleWindowDidUpdate(_:)),
                name: NSWindow.didUpdateNotification,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleWindowWillClose(_:)),
                name: NSWindow.willCloseNotification,
                object: nil
            )
        }

        @objc private func handleWindowDidUpdate(_ notification: Notification) {
            guard let window = notification.object as? NSWindow,
                Self.isSparkleWindow(window)
            else {
                return
            }
            handleObservedUpdateWindow(window)
        }

        @objc private func handleWindowWillClose(_ notification: Notification) {
            guard let window = notification.object as? NSWindow else { return }
            presentedUpdateWindowIDs.remove(ObjectIdentifier(window))
        }

        private func presentVisibleSparkleWindows() {
            for window in NSApp.windows where Self.isSparkleWindow(window) {
                handleObservedUpdateWindow(window)
            }
        }

        private func presentModalAlertWindow() {
            guard let alertWindow = NSApp.modalWindow ?? NSApp.keyWindow else { return }
            Self.configureUpdateWindowChrome(alertWindow)
            centerUpdateWindow(alertWindow)
            bringUpdateWindowToFront(alertWindow)
        }

        private func pruneHiddenUpdateWindowIDs() {
            let visibleIDs = Set(
                NSApp.windows
                    .filter { $0.isVisible && Self.isSparkleWindow($0) }
                    .map(ObjectIdentifier.init)
            )
            presentedUpdateWindowIDs.formIntersection(visibleIDs)
        }

        @discardableResult
        func handleObservedUpdateWindow(
            _ window: NSWindow,
            activate: @escaping @MainActor () -> Void = { AppUpdateManager.activateAppForUpdatePresentation() },
            scheduleRecheck: Bool = true
        ) -> Bool {
            let windowID = ObjectIdentifier(window)
            guard window.isVisible else {
                presentedUpdateWindowIDs.remove(windowID)
                return false
            }

            Self.configureUpdateWindowChrome(window)

            guard presentedUpdateWindowIDs.insert(windowID).inserted else {
                return false
            }

            centerUpdateWindow(window)
            bringUpdateWindowToFront(window, activate: activate)

            if scheduleRecheck {
                DispatchQueue.main.async { [weak self, weak window] in
                    guard let self, let window, window.isVisible else { return }
                    Self.configureUpdateWindowChrome(window)
                    self.bringUpdateWindowToFront(window, activate: activate)
                }
            }
            return true
        }

        private func bringUpdateWindowToFront(
            _ window: NSWindow,
            activate: @MainActor () -> Void = { AppUpdateManager.activateAppForUpdatePresentation() }
        ) {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.collectionBehavior.insert(.moveToActiveSpace)
            activate()
            window.orderFrontRegardless()
            window.makeKeyAndOrderFront(nil)
        }

        private func centerUpdateWindow(_ updateWindow: NSWindow) {
            let mouseLocation = NSEvent.mouseLocation
            let screen =
                NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
                ?? updateWindow.screen
                ?? NSScreen.main
            guard let screen else { return }
            let origin = Self.centeredOrigin(for: updateWindow.frame.size, in: screen.visibleFrame)
            updateWindow.setFrameOrigin(origin)
        }

        private static func activateAppForUpdatePresentation() {
            NSApp.activate(ignoringOtherApps: true)
        }

        static func isSparkleWindow(_ window: NSWindow) -> Bool {
            guard let controller = window.windowController else { return false }
            return isSparkleWindowControllerClass(type(of: controller))
        }

        static func isSparkleWindowControllerClass(_ controllerClass: AnyClass) -> Bool {
            Bundle(for: controllerClass) == Bundle(for: SPUStandardUpdaterController.self)
        }

        static func configureUpdateWindowChrome(_ window: NSWindow) {
            if !window.titlebarAppearsTransparent {
                window.titlebarAppearsTransparent = true
            }
            if window.titlebarSeparatorStyle != .none {
                window.titlebarSeparatorStyle = .none
            }
        }

        static func centeredOrigin(for windowSize: CGSize, in visibleFrame: CGRect) -> CGPoint {
            CGPoint(
                x: visibleFrame.midX - windowSize.width / 2,
                y: visibleFrame.midY - windowSize.height / 2
            )
        }

        private func syncFromUpdater() {
            guard let updater = updaterController?.updater else { return }
            canCheckForUpdates = updater.canCheckForUpdates
            automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
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
                return
                    "Sparkle is disabled because SUFeedURL is missing. Set SPARKLE_FEED_URL in the build settings."
            }

            if publicKey == nil {
                return
                    "Sparkle is disabled because SUPublicEDKey is missing. Set SPARKLE_PUBLIC_ED_KEY in the build settings."
            }

            guard let feedURLString,
                let feedURL = URL(string: feedURLString),
                feedURL.scheme != nil,
                feedURL.host != nil
            else {
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
