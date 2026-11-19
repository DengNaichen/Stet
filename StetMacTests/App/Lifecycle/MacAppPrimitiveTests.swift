#if os(macOS)
    import AppKit
    import Foundation
    import Sparkle
    import StetCore
    import Testing

    @testable import Stet

    @MainActor
    @Suite("Mac App Primitives")
    struct MacAppPrimitiveTests {
        @Test(arguments: [
            (MacOnboardingStep.language, 1, false),
            (MacOnboardingStep.permissions, 2, false),
            (MacOnboardingStep.shortcut, 3, true),
            (MacOnboardingStep.firstSuccess, 4, true),
            (MacOnboardingStep.appearance, 5, false),
            (MacOnboardingStep.done, 5, false),
        ])
        func onboardingStepMetadata(
            _ step: MacOnboardingStep,
            expectedProgressIndex: Int,
            expectedAllowsAudioCapture: Bool
        ) {
            #expect(step.progressIndex == expectedProgressIndex)
            #expect(step.allowsAudioCapture == expectedAllowsAudioCapture)
        }

        @Test func dictationProviderUsesExpectedAPIKeyPlaceholders() {
            #expect(DictationProvider.openAI.apiKeyPlaceholder == "Enter your access key")
            #expect(DictationProvider.groq.apiKeyPlaceholder == "Enter your access key")
            #expect(!DictationProvider.appleIntelligence.requiresAPIKey)
            #expect(!DictationProvider.custom.requiresAPIKey)
            #expect(DictationProvider.custom.apiKeyPlaceholder == "API key (optional)")
        }

        @Test(arguments: [
            ([String: Any](), "Sparkle requires CFBundleShortVersionString and CFBundleVersion."),
            (
                [
                    "CFBundleShortVersionString": "1.2.3",
                    "CFBundleVersion": "7",
                ], "Sparkle is disabled because SUFeedURL is missing. Set SPARKLE_FEED_URL in the build settings."
            ),
            (
                [
                    "CFBundleShortVersionString": "1.2.3",
                    "CFBundleVersion": "7",
                    "SUFeedURL": "https://updates.example.com/appcast.xml",
                ],
                "Sparkle is disabled because SUPublicEDKey is missing. Set SPARKLE_PUBLIC_ED_KEY in the build settings."
            ),
            (
                [
                    "CFBundleShortVersionString": "1.2.3",
                    "CFBundleVersion": "7",
                    "SUFeedURL": "not a url",
                    "SUPublicEDKey": "public-key",
                ], "Sparkle is disabled because SUFeedURL is invalid."
            ),
        ])
        func appUpdateConfigurationIssueReportsExpectedValidationFailure(
            _ infoDictionary: [String: Any],
            expectedMessage: String
        ) {
            #expect(AppUpdateManager.configurationIssue(in: infoDictionary) == expectedMessage)
        }

        @Test func appUpdateConfigurationIssueAcceptsValidConfiguration() {
            let infoDictionary: [String: Any] = [
                "CFBundleShortVersionString": " 1.2.3 ",
                "CFBundleVersion": " 7 ",
                "SUFeedURL": "https://updates.example.com/appcast.xml",
                "SUPublicEDKey": " public-key ",
            ]

            #expect(AppUpdateManager.configurationIssue(in: infoDictionary) == nil)
        }

        @Test func noUpdateFoundErrorRecognizerOnlyMatchesSparkleNoUpdateError() {
            let expected = NSError(domain: SUSparkleErrorDomain, code: 1001)
            let wrongCode = NSError(domain: SUSparkleErrorDomain, code: 1002)
            let wrongDomain = NSError(domain: "CustomErrorDomain", code: 1001)

            #expect(AppUpdateManager.isNoUpdateFoundError(expected))
            #expect(AppUpdateManager.isNoUpdateFoundError(wrongCode) == false)
            #expect(AppUpdateManager.isNoUpdateFoundError(wrongDomain) == false)
        }

        @Test func configureUpdateWindowChromeRemovesTitlebarSeparator() {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 380, height: 140),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.titlebarAppearsTransparent = false
            window.titlebarSeparatorStyle = .line

            AppUpdateManager.configureUpdateWindowChrome(window)

            #expect(window.titlebarAppearsTransparent)
            #expect(window.titlebarSeparatorStyle == .none)
        }

        @Test func sparkleWindowRecognizerMatchesOnlySparkleBundleControllers() {
            let plainWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 200, height: 120),
                styleMask: [.titled],
                backing: .buffered,
                defer: false
            )
            let plainController = NSWindowController(window: plainWindow)
            plainWindow.windowController = plainController

            #expect(!AppUpdateManager.isSparkleWindow(plainWindow))
            #expect(!AppUpdateManager.isSparkleWindowControllerClass(NSWindowController.self))
            #expect(AppUpdateManager.isSparkleWindowControllerClass(SPUStandardUpdaterController.self))
        }

        @Test func handleObservedUpdateWindowPresentsOncePerVisibilityCycleAndAppliesSeamlessChrome() {
            let manager = AppUpdateManager()
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 380, height: 140),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.titlebarAppearsTransparent = false
            window.titlebarSeparatorStyle = .automatic

            var activationCount = 0

            // Hidden windows are not presented.
            #expect(
                !manager.handleObservedUpdateWindow(window, activate: { activationCount += 1 }, scheduleRecheck: false))
            #expect(activationCount == 0)

            // First visible update styles the window seamlessly and activates once.
            window.orderFrontRegardless()
            #expect(
                manager.handleObservedUpdateWindow(window, activate: { activationCount += 1 }, scheduleRecheck: false))
            #expect(activationCount == 1)
            #expect(window.titlebarAppearsTransparent)
            #expect(window.titlebarSeparatorStyle == .none)
            #expect(window.collectionBehavior.contains(.moveToActiveSpace))

            // Repeated didUpdate ticks while still visible must not steal focus again.
            #expect(
                !manager.handleObservedUpdateWindow(window, activate: { activationCount += 1 }, scheduleRecheck: false))
            #expect(activationCount == 1)

            // Hiding then showing again starts a fresh presentation cycle.
            window.orderOut(nil)
            #expect(
                !manager.handleObservedUpdateWindow(window, activate: { activationCount += 1 }, scheduleRecheck: false))
            window.orderFrontRegardless()
            #expect(
                manager.handleObservedUpdateWindow(window, activate: { activationCount += 1 }, scheduleRecheck: false))
            #expect(activationCount == 2)

            window.orderOut(nil)
        }

        @Test func centeredOriginPlacesWindowAtCenterOfVisibleFrame() {
            let visibleFrame = CGRect(x: 100, y: 40, width: 1400, height: 900)
            let origin = AppUpdateManager.centeredOrigin(
                for: CGSize(width: 400, height: 160),
                in: visibleFrame
            )

            #expect(origin == CGPoint(x: 600, y: 410))
        }
    }
#endif
