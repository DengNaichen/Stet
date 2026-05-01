#if os(macOS)
    import AppKit
    import ServiceManagement
    import os

    enum MacAppBehaviorController {
        private static let logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "com.openwhispr.Stet",
            category: "general"
        )
        @MainActor
        static func applyDockVisibility(showInDock: Bool) {
            // `NSApp` can still be nil while the SwiftUI `App` type is initializing.
            NSApplication.shared.setActivationPolicy(showInDock ? .regular : .accessory)
            logger.info("Dock visibility updated: showInDock=\(showInDock)")
        }

        @MainActor
        static func setLaunchAtLogin(_ enabled: Bool) throws {
            guard #available(macOS 13.0, *) else {
                throw CocoaError(.featureUnsupported)
            }

            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }

            logger.info("Launch at login updated: enabled=\(enabled)")
        }

        static func launchAtLoginIsEnabled() -> Bool {
            guard #available(macOS 13.0, *) else { return false }
            return SMAppService.mainApp.status == .enabled
        }
    }
#endif
