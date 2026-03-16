#if os(macOS)
import Foundation
import Testing

@testable import Stet

@MainActor
@Suite("App Environment Logic", .serialized)
struct AppEnvironmentLogicTests {
    @Test func openAINetworkSessionRespectsProxyMode() {
        let disabledSession = OpenAINetworkSession.makeSession(
            for: .init(mode: .disabled, customScheme: .http, customHost: "", customPort: nil)
        )
        let customSession = OpenAINetworkSession.makeSession(
            for: .init(mode: .custom, customScheme: .socks5, customHost: "localhost", customPort: 1080)
        )

        let disabledProxy = disabledSession.configuration.connectionProxyDictionary
        let customProxy = customSession.configuration.connectionProxyDictionary

        #expect((disabledProxy?[kCFNetworkProxiesHTTPEnable as String] as? Int) == 0)
        #expect((customProxy?[kCFNetworkProxiesSOCKSEnable as String] as? Int) == 1)
        #expect((customProxy?[kCFNetworkProxiesSOCKSProxy as String] as? String) == "localhost")
    }

    @Test func appLoggerUsesPreferenceKeysToGateEmission() {
        let defaults = TestSupport.makeUserDefaults()

        #expect(AppLogger.shouldEmit(category: .general, defaults: defaults))
        #expect(!AppLogger.shouldEmit(category: .hotkey, defaults: defaults))

        defaults.set(true, forKey: MacPreferences.hotkeyDebugLoggingEnabled)
        defaults.set(true, forKey: MacPreferences.openAIDebugLoggingEnabled)

        #expect(AppLogger.shouldEmit(category: .hotkey, defaults: defaults))
        #expect(AppLogger.shouldEmit(category: .openAI, defaults: defaults))
        #expect(AppLogger.shouldEmit(category: .appBranch, defaults: defaults))
    }

    @MainActor
    @Test func appUpdateManagerConfigurationIssueValidatesRequiredKeys() {
        #expect(
            AppUpdateManager.configurationIssue(
                in: [
                    "CFBundleVersion": "1",
                    "SUFeedURL": "https://example.com/appcast.xml",
                    "SUPublicEDKey": "abc",
                ]
            ) == "Sparkle requires CFBundleShortVersionString and CFBundleVersion."
        )

        #expect(
            AppUpdateManager.configurationIssue(
                in: [
                    "CFBundleShortVersionString": "1.0",
                    "CFBundleVersion": "1",
                    "SUPublicEDKey": "abc",
                ]
            ) == "Sparkle is disabled because SUFeedURL is missing. Set SPARKLE_FEED_URL in the build settings."
        )

        #expect(
            AppUpdateManager.configurationIssue(
                in: [
                    "CFBundleShortVersionString": "1.0",
                    "CFBundleVersion": "1",
                    "SUFeedURL": "not-a-url",
                    "SUPublicEDKey": "abc",
                ]
            ) == "Sparkle is disabled because SUFeedURL is invalid."
        )
    }
}
#endif
