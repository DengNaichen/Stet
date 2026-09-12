import Foundation
import Testing

@testable import StetCore

struct ModelDownloadMirrorTests {
    private let huggingFace = URL(
        string: "https://huggingface.co/FunAudioLLM/Fun-ASR-Nano-GGUF/resolve/main/funasr-encoder-f16.gguf"
    )!
    private let vad = URL(
        string: "https://huggingface.co/FunAudioLLM/fsmn-vad-GGUF/resolve/main/fsmn-vad.gguf"
    )!
    private let speaker = URL(
        string:
            "https://huggingface.co/csukuangfj/speaker-embedding-models/resolve/main/3dspeaker_speech_campplus_sv_zh-cn_16k-common.onnx"
    )!
    private let unlisted = URL(
        string: "https://huggingface.co/example/unlisted-model/resolve/main/weights.bin"
    )!
    private let github = URL(
        string:
            "https://github.com/k2-fsa/sherpa-onnx/releases/download/speaker-recongition-models/model.onnx"
    )!

    @Test func chinaFunASRPrefersModelScopeThenHfMirror() {
        let urls = ModelDownloadMirror.candidates(for: huggingFace, prefersChina: true)
        #expect(urls.map(\.host) == ["www.modelscope.cn", "hf-mirror.com", "huggingface.co"])
        #expect(
            urls[0].absoluteString
                == "https://www.modelscope.cn/models/FunAudioLLM/Fun-ASR-Nano-GGUF/resolve/master/funasr-encoder-f16.gguf"
        )
        #expect(urls[1].path == huggingFace.path)
        #expect(urls[2] == huggingFace)
    }

    @Test func chinaMapsVadOntoModelScope() {
        let urls = ModelDownloadMirror.candidates(for: vad, prefersChina: true)
        #expect(urls.first?.host == "www.modelscope.cn")
        #expect(urls.first?.path.hasSuffix("/fsmn-vad.gguf") == true)
    }

    @Test func overseasPrefersOfficialHuggingFaceThenMirror() {
        let urls = ModelDownloadMirror.candidates(for: huggingFace, prefersChina: false)
        #expect(urls.map(\.host) == ["huggingface.co", "hf-mirror.com"])
    }

    @Test func unlistedHuggingFaceRepoHasNoModelScopeCopy() {
        #expect(ModelDownloadMirror.modelScopeURL(for: unlisted) == nil)
        let urls = ModelDownloadMirror.candidates(for: unlisted, prefersChina: true)
        #expect(urls.map(\.host) == ["hf-mirror.com", "huggingface.co"])
    }

    @Test func speakerOnnxHasNoModelScopeCopy() {
        #expect(ModelDownloadMirror.modelScopeURL(for: speaker) == nil)
        let urls = ModelDownloadMirror.candidates(
            huggingFace: speaker,
            github: github,
            prefersChina: true
        )
        #expect(urls.map(\.host) == ["hf-mirror.com", "huggingface.co", "github.com"])
    }

    @Test func nonHuggingFaceURLsStayUnchanged() {
        #expect(ModelDownloadMirror.candidates(for: github, prefersChina: true) == [github])
    }

    @Test func chinaSpeakerDownloadsTryHuggingFaceBeforeGitHub() {
        let urls = ModelDownloadMirror.candidates(
            huggingFace: huggingFace,
            github: github,
            prefersChina: true
        )
        #expect(urls.map(\.host) == ["www.modelscope.cn", "hf-mirror.com", "huggingface.co", "github.com"])
    }

    @Test func overseasSpeakerDownloadsTryGitHubBeforeHuggingFace() {
        let urls = ModelDownloadMirror.candidates(
            huggingFace: huggingFace,
            github: github,
            prefersChina: false
        )
        #expect(urls.map(\.host) == ["github.com", "huggingface.co", "hf-mirror.com"])
    }

    @Test func prefersChinaWhenRegionIsChina() throws {
        let locale = Locale(identifier: "en_CN")
        let timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        #expect(ModelDownloadMirror.prefersChinaMirrors(locale: locale, timeZone: timeZone))
    }

    @Test func prefersChinaWhenTimeZoneIsShanghai() throws {
        let locale = Locale(identifier: "en_US")
        let timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        #expect(ModelDownloadMirror.prefersChinaMirrors(locale: locale, timeZone: timeZone))
    }

    @Test func doesNotPreferChinaForUnitedStates() throws {
        let locale = Locale(identifier: "en_US")
        let timeZone = try #require(TimeZone(identifier: "America/New_York"))
        #expect(!ModelDownloadMirror.prefersChinaMirrors(locale: locale, timeZone: timeZone))
    }
}
