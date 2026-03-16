#if os(macOS)
import Foundation
import Testing

@testable import Stet

@MainActor
@Suite("App Branch")
struct AppBranchTests {
    @Test func canonicalizeURLPatternNormalizesSchemeAndTrailingSlash() {
        #expect(AppBranchRule.canonicalizeURLPattern("https://docs.example.com/") == "docs.example.com/*")
        #expect(AppBranchRule.canonicalizeURLPattern("http://docs.example.com/path") == "docs.example.com/path")
        #expect(AppBranchRule.canonicalizeURLPattern("docs.example.com") == "docs.example.com/*")
    }

    @Test func ruleMatchesURLBeforeBundleID() {
        let rule = AppBranchRule(
            name: "Docs",
            prompt: "Use docs style",
            appTargets: [.init(bundleID: "com.apple.Safari", displayName: "Safari")],
            urlPatterns: ["docs.example.com/*"]
        )

        #expect(rule.matches(context: .init(bundleID: "com.apple.Safari", appName: "Safari", browserURL: "https://docs.example.com/page")))
        #expect(rule.matches(context: .init(bundleID: "com.apple.Safari", appName: "Safari", browserURL: nil)))
        #expect(!rule.matches(context: .init(bundleID: "com.apple.TextEdit", appName: "TextEdit", browserURL: "https://apple.com")))
    }

    @Test func resolverPrefersFirstMatchingURLRuleWithPrompt() {
        let rules: [AppBranchRule] = [
            .init(name: "Empty", prompt: "   ", urlPatterns: ["docs.example.com/*"]),
            .init(name: "Docs", prompt: "Write for {{APP_NAME}}", urlPatterns: ["docs.example.com/*"]),
            .init(name: "Bundle", prompt: "Bundle style", appTargets: [.init(bundleID: "com.apple.Safari", displayName: "Safari")]),
        ]

        let resolution = AppBranchPromptResolver.resolve(
            in: rules,
            snapshot: .init(
                context: .init(bundleID: "com.apple.Safari", appName: "Safari", browserURL: "https://docs.example.com/page"),
                capturedAt: .now
            ),
            inputs: .init(
                rawTranscription: "raw",
                text: "text",
                selectedText: "selection",
                targetLanguage: .german,
                context: .init(bundleID: "com.apple.Safari", appName: "Safari", browserURL: "https://docs.example.com/page")
            )
        )

        #expect(resolution.matchedRuleName == "Docs")
        #expect(resolution.renderedPrompt == "Write for Safari")
        #expect(resolution.delivery == .userMessage)
    }

    @Test func promptRendererSubstitutesAllKnownVariables() {
        let rendered = AppBranchPromptResolver.render(
            template: "{{RAW_TRANSCRIPTION}}|{{TEXT}}|{{SELECTED_TEXT}}|{{TARGET_LANGUAGE}}|{{APP_NAME}}|{{BUNDLE_ID}}|{{URL}}",
            inputs: .init(
                rawTranscription: "raw",
                text: "text",
                selectedText: "selected",
                targetLanguage: .spanish,
                context: .init(bundleID: "bundle.id", appName: "Notes", browserURL: "https://example.com")
            )
        )

        #expect(rendered == "raw|text|selected|Spanish|Notes|bundle.id|https://example.com")
    }

    @Test func captureContextStoreUpdatesApplicationAndURL() async {
        let store = CaptureContextStore()
        await store.updateApplication(bundleID: "com.apple.Safari", appName: "Safari")
        await store.updateBrowserURL("https://example.com")

        let snapshot = await store.snapshot()
        #expect(snapshot.context.bundleID == "com.apple.Safari")
        #expect(snapshot.context.appName == "Safari")
        #expect(snapshot.context.browserURL == "https://example.com")
    }
}
#endif
