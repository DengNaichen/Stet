#if os(macOS)
    import Foundation
    import Testing

    @testable import Stet

    @MainActor
    @Suite("Apple Speech Transcription Service")
    struct AppleSpeechTranscriptionServiceTests {
        @Test func mapsStetLanguageCodesToExpectedLocales() {
            guard #available(macOS 26.0, *) else { return }
            #expect(AppleSpeechLocaleResolver.preferredLocaleIdentifier(for: "zh-Hans") == "zh-CN")
            #expect(AppleSpeechLocaleResolver.preferredLocaleIdentifier(for: "zh-Hant") == "zh-TW")
            #expect(AppleSpeechLocaleResolver.preferredLocaleIdentifier(for: "ja") == "ja-JP")
            #expect(AppleSpeechLocaleResolver.preferredLocaleIdentifier(for: "ko") == "ko-KR")
        }

        @Test func failedAssetDownloadCanBeRetried() {
            let state = AppleSpeechAssetState.failed("Network unavailable")

            #expect(state.canDownload)
            #expect(state.errorMessage == "Network unavailable")
        }

        @Test func transcribesFileAndReturnsResolvedLanguage() async throws {
            guard #available(macOS 26.0, *) else { return }
            let fileURL = try makeAudioFile()
            let service = AppleSpeechTranscriptionService(
                resolveLocale: { code in
                    #expect(code == "zh-Hans")
                    return Locale(identifier: "zh-CN")
                },
                transcribeFile: { receivedURL, locale in
                    #expect(receivedURL == fileURL)
                    #expect(locale.identifier == "zh-CN")
                    return "  你好 Stet  "
                }
            )

            let result = try await service.transcribe(
                audioFileAt: fileURL,
                languageCode: "zh-Hans",
                prompt: "ignored",
                audioDurationSeconds: 1
            )

            #expect(result.text == "你好 Stet")
            #expect(result.languageCode == "zh")
        }

        @Test func rejectsEmptyTranscription() async throws {
            guard #available(macOS 26.0, *) else { return }
            let fileURL = try makeAudioFile()
            let service = AppleSpeechTranscriptionService(
                resolveLocale: { _ in Locale(identifier: "en-US") },
                transcribeFile: { _, _ in " \n " }
            )

            await #expect(throws: SpeechServiceError.emptyTranscription) {
                try await service.transcribe(
                    audioFileAt: fileURL,
                    languageCode: "en",
                    prompt: nil,
                    audioDurationSeconds: nil
                )
            }
        }

        private func makeAudioFile() throws -> URL {
            let url = TestSupport.temporaryFileURL("apple-speech-audio", ext: "wav")
            try Data("audio".utf8).write(to: url)
            return url
        }
    }
#endif
