#if os(macOS)
    import Foundation
    import Sparkle
    import Testing

    @testable import Stet

    @MainActor
    @Suite("Mac App Primitives")
    struct MacAppPrimitiveTests {
        @Test(arguments: [
            (MacOnboardingStep.download, 1, false),
            (MacOnboardingStep.apiKey, 2, false),
            (MacOnboardingStep.permissions, 3, false),
            (MacOnboardingStep.shortcut, 4, true),
            (MacOnboardingStep.firstSuccess, 5, true),
            (MacOnboardingStep.appearance, 6, false),
            (MacOnboardingStep.done, 6, false),
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
    }
#endif
