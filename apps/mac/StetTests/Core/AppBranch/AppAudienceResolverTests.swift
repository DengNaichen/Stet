#if os(macOS)
import Foundation
import Testing

@testable import Stet

extension AppBranchTests {
    @Test("AppAudience isAI property returns true for AI audience")
    func appAudienceIsAIPropertyReturnsTrueForAIAudience() {
        #expect(AppAudience.ai.isAI == true)
        #expect(AppAudience.human.isAI == false)
    }

    @Test("AppAudienceResolver is case-insensitive for bundle identifiers")
    func appAudienceResolverIsCaseInsensitiveForBundleIdentifiers() {
        let audience1 = AppAudienceResolver.resolve(
            bundleIdentifier: "COM.OPENAI.CHATGPT",
            localizedName: "Something"
        )
        let audience2 = AppAudienceResolver.resolve(
            bundleIdentifier: "com.openai.chatgpt",
            localizedName: "Something"
        )
        let audience3 = AppAudienceResolver.resolve(
            bundleIdentifier: "Com.OpenAI.ChatGPT",
            localizedName: "Something"
        )

        #expect(audience1 == .ai)
        #expect(audience2 == .ai)
        #expect(audience3 == .ai)
    }

    @Test("AppAudienceResolver is case-insensitive for localized names")
    func appAudienceResolverIsCaseInsensitiveForLocalizedNames() {
        let audience1 = AppAudienceResolver.resolve(
            bundleIdentifier: "com.example.unknown",
            localizedName: "CHATGPT"
        )
        let audience2 = AppAudienceResolver.resolve(
            bundleIdentifier: "com.example.unknown",
            localizedName: "chatgpt"
        )
        let audience3 = AppAudienceResolver.resolve(
            bundleIdentifier: "com.example.unknown",
            localizedName: "ChatGPT"
        )

        #expect(audience1 == .ai)
        #expect(audience2 == .ai)
        #expect(audience3 == .ai)
    }

    @Test("AppAudienceResolver handles whitespace in names")
    func appAudienceResolverHandlesWhitespaceInNames() {
        let audience1 = AppAudienceResolver.resolve(
            bundleIdentifier: "com.example.unknown",
            localizedName: "  ChatGPT  "
        )
        let audience2 = AppAudienceResolver.resolve(
            bundleIdentifier: "  com.openai.chatgpt  ",
            localizedName: "Something"
        )

        #expect(audience1 == .ai)
        #expect(audience2 == .ai)
    }

    @Test("AppAudienceResolver recognizes partial matches in bundle identifiers")
    func appAudienceResolverRecognizesPartialMatchesInBundleIdentifiers() {
        let audience = AppAudienceResolver.resolve(
            bundleIdentifier: "com.company.vscode.extension",
            localizedName: "Some Extension"
        )

        #expect(audience == .ai)
    }

    @Test("AppAudienceResolver recognizes partial matches in localized names")
    func appAudienceResolverRecognizesPartialMatchesInLocalizedNames() {
        let audience = AppAudienceResolver.resolve(
            bundleIdentifier: "com.example.unknown",
            localizedName: "My Custom Cursor Editor"
        )

        #expect(audience == .ai)
    }

    @Test("AppAudienceResolver returns human for unknown apps")
    func appAudienceResolverReturnsHumanForUnknownApps() {
        let audience = AppAudienceResolver.resolve(
            bundleIdentifier: "com.example.randomapp",
            localizedName: "Random App"
        )

        #expect(audience == .human)
    }

    @Test("AppAudienceResolver recognizes all documented AI tools")
    func appAudienceResolverRecognizesAllDocumentedAITools() {
        let aiTools = [
            ("com.android.studio", "Android Studio"),
            ("com.example.aider", "Aider"),
            ("dev.antigravity.app", "AntiGravity"),
            ("com.example.augment", "Augment"),
            ("com.example.bolt", "Bolt"),
            ("com.openai.chatgpt", "ChatGPT"),
            ("com.anthropic.claude", "Claude"),
            ("com.example.cline", "Cline"),
            ("com.jetbrains.clion", "CLion"),
            ("com.example.codex", "Codex"),
            ("com.codeium.app", "Codeium"),
            ("com.example.continue", "Continue"),
            ("com.google.gemini", "Gemini"),
            ("com.github.copilot", "Copilot"),
            ("com.cursor.app", "Cursor"),
            ("com.jetbrains.fleet", "Fleet"),
            ("com.jetbrains.goland", "GoLand"),
            ("com.jetbrains.intellij", "IntelliJ IDEA"),
            ("com.kiro.app", "Kiro"),
            ("com.perplexity.app", "Perplexity"),
            ("com.jetbrains.phpstorm", "PhpStorm"),
            ("com.poe.app", "Poe"),
            ("com.jetbrains.pycharm", "PyCharm"),
            ("com.replit.app", "Replit"),
            ("com.example.roocode", "Roo Code"),
            ("com.jetbrains.rider", "Rider"),
            ("com.example.trae", "Trae"),
            ("com.microsoft.vscode", "Visual Studio Code"),
            ("com.warp.terminal", "Warp"),
            ("com.jetbrains.webstorm", "WebStorm"),
            ("com.windsurf.app", "Windsurf"),
            ("com.apple.dt.xcode", "Xcode"),
            ("dev.zed.app", "Zed")
        ]

        for (bundleID, name) in aiTools {
            let audienceByBundle = AppAudienceResolver.resolve(
                bundleIdentifier: bundleID,
                localizedName: "Unknown"
            )
            let audienceByName = AppAudienceResolver.resolve(
                bundleIdentifier: "com.example.unknown",
                localizedName: name
            )

            #expect(audienceByBundle == .ai, "Expected \(bundleID) to be recognized as AI")
            #expect(audienceByName == .ai, "Expected \(name) to be recognized as AI")
        }
    }

    @Test("AppAudience can be encoded and decoded")
    func appAudienceCanBeEncodedAndDecoded() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let aiData = try encoder.encode(AppAudience.ai)
        let humanData = try encoder.encode(AppAudience.human)

        let decodedAI = try decoder.decode(AppAudience.self, from: aiData)
        let decodedHuman = try decoder.decode(AppAudience.self, from: humanData)

        #expect(decodedAI == .ai)
        #expect(decodedHuman == .human)
    }
}
#endif
