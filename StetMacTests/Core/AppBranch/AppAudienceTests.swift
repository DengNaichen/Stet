#if os(macOS)
    import StetCore
    import Testing

    @testable import Stet

    extension AppBranchTests {
        @Test("App audience defaults to human for ordinary apps")
        func appAudienceDefaultsToHumanForOrdinaryApps() {
            let appInfo = AppInfo(
                bundleIdentifier: "com.apple.TextEdit",
                localizedName: "TextEdit",
                processIdentifier: 101,
                isOwnHostApplication: false,
                runningApplication: nil
            )

            #expect(appInfo.audience == .human)
        }

        @Test("App audience recognizes AI-facing apps by name")
        func appAudienceRecognizesAIFacingAppsByName() {
            let appInfo = AppInfo(
                bundleIdentifier: "com.example.unknown",
                localizedName: "ChatGPT",
                processIdentifier: 202,
                isOwnHostApplication: false,
                runningApplication: nil
            )

            #expect(appInfo.audience == .ai)
            #expect(appInfo.audience.isAI)
        }

        @Test("App audience recognizes Codex-style AI coding apps by name")
        func appAudienceRecognizesCodexStyleAICodingAppsByName() {
            let codexAudience = AppAudienceResolver.resolve(
                bundleIdentifier: "com.example.unknown",
                localizedName: "OpenAI Codex"
            )
            let clineAudience = AppAudienceResolver.resolve(
                bundleIdentifier: "com.example.unknown",
                localizedName: "Cline"
            )
            let rooAudience = AppAudienceResolver.resolve(
                bundleIdentifier: "com.example.unknown",
                localizedName: "Roo Code"
            )

            #expect(codexAudience == .ai)
            #expect(clineAudience == .ai)
            #expect(rooAudience == .ai)
        }
    }
#endif
