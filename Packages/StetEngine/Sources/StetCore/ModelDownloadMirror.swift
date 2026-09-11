import Foundation

/// Rewrites Hugging Face model URLs onto China-reachable hosts and keeps the
/// official host as fallback. GitHub releases stay as extra fallbacks.
///
/// ModelScope is used only for repositories verified to publish the same
/// filenames. The sherpa-onnx speaker `.onnx` is not one of those.
public enum ModelDownloadMirror: Sendable {
    public static let huggingFaceOrigin = "huggingface.co"
    public static let huggingFaceChinaOrigin = "hf-mirror.com"
    public static let modelScopeOrigin = "www.modelscope.cn"

    /// Hugging Face repos that host the same files on ModelScope.
    private static let modelScopeRepos: Set<String> = [
        "FunAudioLLM/Fun-ASR-Nano-GGUF",
        "FunAudioLLM/fsmn-vad-GGUF",
    ]

    private static let chinaTimeZoneIdentifiers: Set<String> = [
        "Asia/Shanghai",
        "Asia/Chongqing",
        "Asia/Harbin",
        "Asia/Urumqi",
        "Asia/Kashgar",
        "PRC",
    ]

    public static let urlSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        return URLSession(configuration: configuration)
    }()

    public static func prefersChinaMirrors(
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> Bool {
        if locale.region?.identifier == "CN" {
            return true
        }
        return chinaTimeZoneIdentifiers.contains(timeZone.identifier)
    }

    public static func rewriting(_ url: URL, host: String) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.host = host
        return components.url
    }

    public static func modelScopeURL(for huggingFaceURL: URL) -> URL? {
        guard huggingFaceURL.host == huggingFaceOrigin else { return nil }
        let parts = huggingFaceURL.path.split(separator: "/").map(String.init)
        guard parts.count >= 5, parts[2] == "resolve" else { return nil }
        let repo = "\(parts[0])/\(parts[1])"
        guard modelScopeRepos.contains(repo) else { return nil }
        let file = parts[4...].joined(separator: "/")
        return URL(string: "https://\(modelScopeOrigin)/models/\(repo)/resolve/master/\(file)")
    }

    public static func candidates(
        for official: URL,
        prefersChina: Bool = prefersChinaMirrors()
    ) -> [URL] {
        guard official.host == huggingFaceOrigin else { return [official] }
        let modelScope = modelScopeURL(for: official)
        let mirror = rewriting(official, host: huggingFaceChinaOrigin)
        if prefersChina {
            return uniqued([modelScope, mirror, official].compactMap { $0 })
        }
        return uniqued([official, mirror].compactMap { $0 })
    }

    public static func candidates(
        huggingFace official: URL,
        github: URL,
        prefersChina: Bool = prefersChinaMirrors()
    ) -> [URL] {
        let fromHuggingFace = candidates(for: official, prefersChina: prefersChina)
        if prefersChina {
            return uniqued(fromHuggingFace + [github])
        }
        return uniqued([github] + fromHuggingFace)
    }

    private static func uniqued(_ urls: [URL]) -> [URL] {
        var seen = Set<URL>()
        return urls.filter { seen.insert($0).inserted }
    }
}
