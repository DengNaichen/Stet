import Speech
import StetASR
import Testing

struct AppleSpeechAssetsTests {
    @Test func localeAliasesAndExplicitRegions() {
        guard #available(macOS 26.0, iOS 26.0, *) else { return }
        for (identifier, expected) in [
            ("zh", "zh-CN"), ("zh-Hans", "zh-CN"), ("zh-Hant", "zh-TW"),
            ("en-GB", "en-GB"), ("zh-TW", "zh-TW"), ("ja", "ja-JP"), ("ko", "ko-KR"),
        ] {
            #expect(AppleSpeechLocaleResolver.preferredLocaleIdentifier(for: identifier) == expected)
        }
    }

    @Test func inventoryStatusAndRetryability() {
        guard #available(macOS 26.0, iOS 26.0, *) else { return }
        #expect(AppleSpeechAssetStatus(inventory: .installed).isInstalled)
        #expect(AppleSpeechAssetStatus(inventory: .supported).canDownload)
        #expect(AppleSpeechAssetStatus(inventory: .downloading).isDownloading)
        #expect(AppleSpeechAssetStatus(inventory: .unsupported) == .unsupportedLocale)
        #expect(AppleSpeechAssetStatus.failed("offline").canDownload)
    }
}
