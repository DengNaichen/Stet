#if os(macOS)
    import Foundation
    import Testing

    @testable import Stet

    extension AppBranchTests {
        @Test("AppInfo equality compares all relevant fields")
        func appInfoEqualityComparesAllRelevantFields() {
            let app1 = AppInfo(
                bundleIdentifier: "com.apple.Safari",
                localizedName: "Safari",
                processIdentifier: 42,
                isOwnHostApplication: false,
                runningApplication: nil
            )

            let app2 = AppInfo(
                bundleIdentifier: "com.apple.Safari",
                localizedName: "Safari",
                processIdentifier: 42,
                isOwnHostApplication: false,
                runningApplication: nil
            )

            #expect(app1 == app2)
        }

        @Test("AppInfo inequality when bundle identifiers differ")
        func appInfoInequalityWhenBundleIdentifiersDiffer() {
            let app1 = AppInfo(
                bundleIdentifier: "com.apple.Safari",
                localizedName: "Safari",
                processIdentifier: 42,
                isOwnHostApplication: false,
                runningApplication: nil
            )

            let app2 = AppInfo(
                bundleIdentifier: "com.apple.Mail",
                localizedName: "Safari",
                processIdentifier: 42,
                isOwnHostApplication: false,
                runningApplication: nil
            )

            #expect(app1 != app2)
        }

        @Test("AppInfo inequality when localized names differ")
        func appInfoInequalityWhenLocalizedNamesDiffer() {
            let app1 = AppInfo(
                bundleIdentifier: "com.apple.Safari",
                localizedName: "Safari",
                processIdentifier: 42,
                isOwnHostApplication: false,
                runningApplication: nil
            )

            let app2 = AppInfo(
                bundleIdentifier: "com.apple.Safari",
                localizedName: "Web Browser",
                processIdentifier: 42,
                isOwnHostApplication: false,
                runningApplication: nil
            )

            #expect(app1 != app2)
        }

        @Test("AppInfo inequality when process identifiers differ")
        func appInfoInequalityWhenProcessIdentifiersDiffer() {
            let app1 = AppInfo(
                bundleIdentifier: "com.apple.Safari",
                localizedName: "Safari",
                processIdentifier: 42,
                isOwnHostApplication: false,
                runningApplication: nil
            )

            let app2 = AppInfo(
                bundleIdentifier: "com.apple.Safari",
                localizedName: "Safari",
                processIdentifier: 99,
                isOwnHostApplication: false,
                runningApplication: nil
            )

            #expect(app1 != app2)
        }

        @Test("AppInfo inequality when isOwnHostApplication differs")
        func appInfoInequalityWhenIsOwnHostApplicationDiffers() {
            let app1 = AppInfo(
                bundleIdentifier: "com.apple.Safari",
                localizedName: "Safari",
                processIdentifier: 42,
                isOwnHostApplication: false,
                runningApplication: nil
            )

            let app2 = AppInfo(
                bundleIdentifier: "com.apple.Safari",
                localizedName: "Safari",
                processIdentifier: 42,
                isOwnHostApplication: true,
                runningApplication: nil
            )

            #expect(app1 != app2)
        }

        @Test("AppInfo audience property returns correct value")
        func appInfoAudiencePropertyReturnsCorrectValue() {
            let humanApp = AppInfo(
                bundleIdentifier: "com.apple.Safari",
                localizedName: "Safari",
                processIdentifier: 42,
                isOwnHostApplication: false,
                runningApplication: nil
            )

            let aiApp = AppInfo(
                bundleIdentifier: "com.openai.chatgpt",
                localizedName: "ChatGPT",
                processIdentifier: 99,
                isOwnHostApplication: false,
                runningApplication: nil
            )

            #expect(humanApp.audience == .human)
            #expect(aiApp.audience == .ai)
        }

        @Test("AppInfo initializes with all provided values")
        func appInfoInitializesWithAllProvidedValues() {
            let appInfo = AppInfo(
                bundleIdentifier: "com.example.app",
                localizedName: "Example App",
                processIdentifier: 1234,
                isOwnHostApplication: true,
                runningApplication: nil
            )

            #expect(appInfo.bundleIdentifier == "com.example.app")
            #expect(appInfo.localizedName == "Example App")
            #expect(appInfo.processIdentifier == 1234)
            #expect(appInfo.isOwnHostApplication == true)
            #expect(appInfo.runningApplication == nil)
        }
    }
#endif
